# FU Mesh — Conformance Harness Contract

`vectors.json` (spec `fu-mesh-conformance`, **version 2**) is generated from
the Elixir reference (`Fu.Mesh.Identity` + `Fu.Mesh.V3`, 130 tests).

**A runtime is conformant iff it reproduces every vector byte/value-exact.**
Where this prose and `vectors.json` disagree, the vectors win.

Regenerate: `mix run --no-start bench/conformance_vectors.exs`

---

## Primitives the runtime must implement identically

- **Ed25519**, RFC 8032. Signatures are deterministic (same key + message ⇒
  same signature bytes).
- **Deterministic keypair from a 32-byte seed.** Same seed ⇒ same public
  key on every conformant runtime. (Reference uses
  `:crypto.generate_key(:eddsa, :ed25519, seed)`.)
- **address** = `lower_hex(SHA-256(public_key))` truncated to the first
  **16 hex chars**.
- **canonical(att)** = `"{match}|{player}|{delta_milli}"`, UTF-8, where
  `delta_milli = round(delta * 1000)` with **round-half-away-from-zero**.
  It is a plain integer — there is NO float formatting on the wire.
  `player` is opaque UTF-8 and must not contain `|`.
  Only `match`, `player`, `delta` are signed; `sig`, `author_pub`,
  `witnesses`, `size` are excluded.
- **rank**: band `[30.0, 100.0]`, start `50.0`; unknown player ⇒ `50.0`.
- **witnessed rank** = median of the witnesses' local views, the subject's
  own copy excluded; median index = `floor((n-1)/2)` of the sorted views;
  empty witness set ⇒ `50.0`.

---

## Procedure

```
0. Load vectors.json.
   ASSERT doc.spec == "fu-mesh-conformance"
   ASSERT doc.version == 2                 # refuse to run against any other version

1. identity[]
   for each v:
     (pub, priv) = keypair_from_seed(hex_decode(v.seed_hex))
     ASSERT hex(pub)            == v.public_hex
     ASSERT address(pub)        == v.address
     if v has sign_payload:
       ASSERT hex(sign(priv, utf8(v.sign_payload))) == v.signature_hex

2. canonical_attestations[]
   (_, priv) = keypair_from_seed(hex_decode(identity[0].seed_hex))
   for each c:
     ASSERT canonical(c.match, c.player, c.delta) == c.canonical
     ASSERT hex(sign(priv, utf8(c.canonical)))     == c.signature_hex
   # NB: c.delta in JSON may be a float (e.g. 0.30000000000000004);
   # the runtime MUST collapse it via round(delta*1000) to the same integer.

3. mesh.signed_ingest
   build att = attest(1,"p",1.5,[]) signed by identity[0] key
   node w1 = new_node("w1",["p"]); ingest_signed(w1, att)
   ASSERT rank(w1,"p")                        == mesh.signed_ingest.valid_att_rank        # 51.5
   forged = att with delta:=99.0 (signature unchanged)
   node w3 = new_node("w3",["p"]); ingest_signed(w3, forged)
   ASSERT knows?(w3,"p")                      == mesh.signed_ingest.forged_att_known       # false
   ASSERT witnessed_rank({w1,w2},["w1","w2"],"p") == mesh.signed_ingest.witnessed_rank_friends  # 51.5

4. bootstrap
   reproduce the provisional-witness scenario (acquaintance threshold from §6)
   ASSERT sort(provisional_witnesses(nodes,"orphan")) == bootstrap.provisional_witnesses  # ["o1","o2"]
   ASSERT recoverable_rank(nodes,[],"orphan")          == bootstrap.recoverable_rank_no_friends  # 51.5
   ASSERT ("orphan" not in provisional_witnesses)      == bootstrap.self_excluded          # true

PASS iff every assertion holds; exit non-zero on the first failure.
```

## CI gate

The harness is **the** acceptance test, not a courtesy. Wire it into the
runtime's CI: a normative change bumps `version`; the runtime declares the
version it targets and the harness refuses any mismatch (step 0). No green
harness ⇒ not a Football United node.

## Constants (frozen at v2, from the reference)

| name | value |
|---|---|
| window `W` (pending kept per player) | 8 |
| stranger TTL (idle ticks) | 4 |
| acquaintance threshold (encounters) | 3 |
| acquaintance decay (idle ticks) | 6 |
| rank band / start | [30.0, 100.0] / 50.0 |
| address length (hex chars) | 16 |
| delta scale | ×1000, round-half-away-from-zero |
