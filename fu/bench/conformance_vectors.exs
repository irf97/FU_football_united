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

doc = %{
  spec: "fu-mesh-conformance",
  version: 3,
  generated_from: "Fu.Mesh.Identity + Fu.Mesh.V3 (Elixir reference)",
  notes: [
    "canonical = \"{match}|{player}|{delta_milli}\"; delta_milli = round(delta*1000), round-half-away-from-zero — a plain integer, NO float formatting",
    "player is opaque UTF-8 and MUST NOT contain the '|' delimiter",
    "Ed25519 per RFC 8032 — signatures are deterministic and reproducible",
    "address = lowercase hex of SHA-256(public_key), first 16 chars",
    "rank band [30.0,100.0], start 50.0; witnessed rank = median, self-excluded",
    "v2 superseded v1: delta encoding moved from float-string to milli-integer",
    "v3 adds the wire section: byte-exact frame (magic FU, ver 2, len-prefixed, sha256[0..4] digest)"
  ],
  identity: identity,
  canonical_attestations: canonical,
  mesh: mesh,
  bootstrap: bootstrap,
  wire: wire
}

File.mkdir_p!("conformance")
path = "conformance/vectors.json"
File.write!(path, Jason.encode!(doc, pretty: true) <> "\n")
IO.puts("wrote #{path} — #{:erlang.byte_size(File.read!(path))} bytes")
IO.puts("identity[0].address=#{Identity.address(pub1)}  witnessed_rank=#{mesh.signed_ingest.witnessed_rank_friends}  prov=#{inspect(bootstrap.provisional_witnesses)}")
