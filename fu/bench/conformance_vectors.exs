# Emits authoritative conformance vectors from the REFERENCE model.
#
#   mix run --no-start bench/conformance_vectors.exs
#
# Output: conformance/vectors.json — deterministic input→output pairs the
# Rust runtime MUST reproduce exactly. Ed25519 signing is deterministic
# (RFC 8032), so signature bytes are stable expected values, not samples.

alias Fu.Mesh.{Identity, V3, Wire}

hex = fn b -> Base.encode16(b, case: :lower) end
seed1 = :binary.copy(<<1>>, 32)
seed2 = :binary.copy(<<2>>, 32)
{pub1, priv1} = Identity.keypair_from_seed(seed1)
{pub2, _priv2} = Identity.keypair_from_seed(seed2)

# --- Identity vectors -------------------------------------------------------
id_payload = Identity.canonical(V3.attest(1, "p", 1.5, []))

identity = [
  %{
    seed_hex: hex.(seed1),
    public_hex: hex.(pub1),
    address: Identity.address(pub1),
    sign_payload: id_payload,
    signature_hex: hex.(Identity.sign(priv1, id_payload))
  },
  %{
    seed_hex: hex.(seed2),
    public_hex: hex.(pub2),
    address: Identity.address(pub2)
  }
]

# --- Canonical attestation encoding (the exact bytes that get signed) -------
# Single source of truth: Fu.Mesh.Identity.canonical/1 (milli-integer delta).
canonical =
  for {m, p, d} <- [{1, "p", 1.5}, {7, "orphan", -0.8}, {12, "gk", 0.3}, {2, "p", 0.1 + 0.2}] do
    payload = Identity.canonical(V3.attest(m, p, d, []))
    %{match: m, player: p, delta: d, canonical: payload, signature_hex: hex.(Identity.sign(priv1, payload))}
  end

# --- Mesh scenario: signed ingest + witnessed rank -------------------------
att = V3.attest(1, "p", 1.5, []) |> Identity.sign_attest(priv1, pub1)
forged = %{att | delta: 99.0}

w1 = V3.new_node("w1", ["p"]) |> V3.ingest_signed(att)
w2 = V3.new_node("w2", ["p"]) |> V3.ingest_signed(att)
dropped = V3.new_node("w3", ["p"]) |> V3.ingest_signed(forged)
nodes = %{"w1" => w1, "w2" => w2, "p" => V3.new_node("p", [])}

mesh = %{
  signed_ingest: %{
    valid_att_rank: V3.rank(w1, "p"),
    forged_att_known: V3.knows?(dropped, "p"),
    witnessed_rank_friends: V3.witnessed_rank(nodes, ["w1", "w2"], "p")
  }
}

# --- Provisional-witness (friendless bootstrap) ----------------------------
a = V3.attest(1, "orphan", 1.5, [])

acq = fn id ->
  V3.new_node(id, [])
  |> (fn n -> Enum.reduce(1..V3.acq_threshold(), n, fn _, x -> V3.met(x, "orphan") end) end).()
  |> V3.ingest(a)
end

onodes = %{"o1" => acq.("o1"), "o2" => acq.("o2"), "orphan" => V3.new_node("orphan", []) |> V3.ingest(a)}

bootstrap = %{
  provisional_witnesses: V3.provisional_witnesses(onodes, "orphan") |> Enum.sort(),
  recoverable_rank_no_friends: V3.recoverable_rank(onodes, [], "orphan"),
  self_excluded: "orphan" not in V3.provisional_witnesses(onodes, "orphan")
}

# --- Wire framing: byte-exact frame for a deterministic signed att --------
wire_att = V3.attest(1, "p", 1.5, ["w1"]) |> Identity.sign_attest(priv1, pub1)
wire_frame = Wire.encode(wire_att)

wire = %{
  attestation: %{match: 1, player: "p", delta: 1.5, witnesses: ["w1"]},
  signer_seed_hex: hex.(seed1),
  frame_hex: hex.(wire_frame),
  frame_bytes: byte_size(wire_frame),
  max_payload: Wire.max_payload(),
  mtu_example: %{mtu: 16, chunk_count: length(Wire.chunks(wire_frame, 16))}
}

# --- Pipeline capstone: convergence over bytes only -----------------------
pseed = :binary.copy(<<8>>, 32)
{ppub, ppriv} = Identity.keypair_from_seed(pseed)
patt = V3.attest(1, "P", 1.5, ["W1", "W2"]) |> Identity.sign_attest(ppriv, ppub)

wire_hop = fn a, mtu ->
  {:ok, [g], ""} = a |> Wire.encode() |> Wire.chunks(mtu) |> IO.iodata_to_binary() |> Wire.decode_stream()
  g
end

pw1 = V3.new_node("W1", ["P"]) |> V3.ingest_signed(wire_hop.(patt, 11))
[pheld] = V3.held_attestations(pw1, "P")
pw2 = V3.new_node("W2", ["P"]) |> V3.ingest_signed(wire_hop.(pheld, 7))
pnodes = %{"W1" => pw1, "W2" => pw2, "P" => V3.new_node("P", [])}

{:ok, pforged, ""} = patt |> Map.put(:delta, 99.0) |> Wire.encode() |> Wire.decode()

pipeline = %{
  signer_seed_hex: hex.(pseed),
  attestation: %{match: 1, player: "P", delta: 1.5, witnesses: ["W1", "W2"]},
  mtu_a: 11,
  mtu_b: 7,
  final_witnessed_rank: V3.witnessed_rank(pnodes, ["W1", "W2"], "P"),
  forged_verified: Identity.verified?(pforged)
}

# --- Adversarial: the security boundary, locked ---------------------------
{ahp, ahpriv} = Identity.keypair_from_seed(:binary.copy(<<20>>, 32))
{acp, acpriv} = Identity.keypair_from_seed(:binary.copy(<<21>>, 32))
ah = V3.attest(1, "P", 1.5, []) |> Identity.sign_attest(ahpriv, ahp)
ac = V3.attest(2, "P", 50.0, []) |> Identity.sign_attest(acpriv, acp)
awit = fn id, atts -> Enum.reduce(atts, V3.new_node(id, ["P"]), &V3.ingest_signed(&2, &1)) end

minority =
  %{"w1" => awit.("w1", [ah]), "w2" => awit.("w2", [ah]), "w3" => awit.("w3", [ah]),
    "w4" => awit.("w4", [ah, ac]), "w5" => awit.("w5", [ah, ac])}

majority =
  %{"w1" => awit.("w1", [ah]), "w2" => awit.("w2", [ah]), "w3" => awit.("w3", [ah, ac]),
    "w4" => awit.("w4", [ah, ac]), "w5" => awit.("w5", [ah, ac])}

{:ok, amang, ""} = (with {:ok, g, ""} <- Wire.decode(Wire.encode(ah)), do: Wire.decode(Wire.encode(%{g | delta: 9.9})))

adversarial = %{
  honest_signer_seed_hex: hex.(:binary.copy(<<20>>, 32)),
  collude_signer_seed_hex: hex.(:binary.copy(<<21>>, 32)),
  collusion_minority_2of5: V3.witnessed_rank(minority, ~w(w1 w2 w3 w4 w5), "P"),
  collusion_majority_3of5: V3.witnessed_rank(majority, ~w(w1 w2 w3 w4 w5), "P"),
  byzantine_relay_delivered: Identity.verified?(amang)
}

doc = %{
  spec: "fu-mesh-conformance",
  version: 5,
  generated_from: "Fu.Mesh.Identity + Fu.Mesh.V3 (Elixir reference)",
  notes: [
    "canonical = \"{match}|{player}|{delta_milli}\"; delta_milli = round(delta*1000), round-half-away-from-zero — a plain integer, NO float formatting",
    "player is opaque UTF-8 and MUST NOT contain the '|' delimiter",
    "Ed25519 per RFC 8032 — signatures are deterministic and reproducible",
    "address = lowercase hex of SHA-256(public_key), first 16 chars",
    "rank band [30.0,100.0], start 50.0; witnessed rank = median, self-excluded",
    "v2 superseded v1: delta encoding moved from float-string to milli-integer",
    "v3 added the wire section: byte-exact frame (magic FU, ver 2, len-prefixed, sha256[0..4] digest)",
    "v4 added the pipeline capstone: convergence using ONLY framed bytes (sign→encode→chunk→stream→ingest_signed→relay→witnessed rank)",
    "v5 adds adversarial: minority collusion cannot move the median, majority can (stated limit), byzantine relay cannot inject (integrity)"
  ],
  identity: identity,
  canonical_attestations: canonical,
  mesh: mesh,
  bootstrap: bootstrap,
  wire: wire,
  pipeline: pipeline,
  adversarial: adversarial
}

File.mkdir_p!("conformance")
path = "conformance/vectors.json"
File.write!(path, Jason.encode!(doc, pretty: true) <> "\n")
IO.puts("wrote #{path} — #{:erlang.byte_size(File.read!(path))} bytes")
IO.puts("identity[0].address=#{Identity.address(pub1)}  witnessed_rank=#{mesh.signed_ingest.witnessed_rank_friends}  prov=#{inspect(bootstrap.provisional_witnesses)}")
