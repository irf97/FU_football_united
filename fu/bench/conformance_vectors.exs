# Emits authoritative conformance vectors from the REFERENCE model.
#
#   mix run --no-start bench/conformance_vectors.exs
#
# Output: conformance/vectors.json — deterministic input→output pairs the
# Rust runtime MUST reproduce exactly. Ed25519 signing is deterministic
# (RFC 8032), so signature bytes are stable expected values, not samples.

alias Fu.Mesh.{Identity, V3}

hex = fn b -> Base.encode16(b, case: :lower) end
seed1 = :binary.copy(<<1>>, 32)
seed2 = :binary.copy(<<2>>, 32)
{pub1, priv1} = Identity.keypair_from_seed(seed1)
{pub2, _priv2} = Identity.keypair_from_seed(seed2)

# --- Identity vectors -------------------------------------------------------
identity = [
  %{
    seed_hex: hex.(seed1),
    public_hex: hex.(pub1),
    address: Identity.address(pub1),
    sign_payload: "1|p|1.5",
    signature_hex: hex.(Identity.sign(priv1, "1|p|1.5"))
  },
  %{
    seed_hex: hex.(seed2),
    public_hex: hex.(pub2),
    address: Identity.address(pub2)
  }
]

# --- Canonical attestation encoding (the exact bytes that get signed) -------
canon = fn m, p, d -> "#{m}|#{p}|#{d}" end

canonical =
  for {m, p, d} <- [{1, "p", 1.5}, {7, "orphan", -0.8}, {12, "gk", 0.3}] do
    payload = canon.(m, p, d)
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

doc = %{
  spec: "fu-mesh-conformance",
  version: 1,
  generated_from: "Fu.Mesh.Identity + Fu.Mesh.V3 (Elixir reference)",
  notes: [
    "canonical attestation encoding = \"#{0}\" pattern: match|player|delta",
    "Ed25519 per RFC 8032 — signatures are deterministic and reproducible",
    "address = lowercase hex of SHA-256(public_key), first 16 chars",
    "rank band [30.0,100.0], start 50.0; witnessed rank = median, self-excluded"
  ],
  identity: identity,
  canonical_attestations: canonical,
  mesh: mesh,
  bootstrap: bootstrap
}

File.mkdir_p!("conformance")
path = "conformance/vectors.json"
File.write!(path, Jason.encode!(doc, pretty: true) <> "\n")
IO.puts("wrote #{path} — #{:erlang.byte_size(File.read!(path))} bytes")
IO.puts("identity[0].address=#{Identity.address(pub1)}  witnessed_rank=#{mesh.signed_ingest.witnessed_rank_friends}  prov=#{inspect(bootstrap.provisional_witnesses)}")
