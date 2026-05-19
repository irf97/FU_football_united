# FU Mesh — Conformance Harness Contract

`vectors.json` (spec `fu-mesh-conformance`, **version 5**) is generated from
the Elixir reference (Identity + V3 + Wire).

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
   ASSERT doc.version == 5                 # refuse to run against any other version

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

5. wire
   (pub,priv) = keypair_from_seed(hex_decode(wire.signer_seed_hex))
   att   = sign_attest(attest(wire.attestation...), priv, pub)
   frame = wire_encode(att)
   ASSERT hex(frame)            == wire.frame_hex          # byte-exact
   ASSERT len(frame)            == wire.frame_bytes
   ASSERT wire_decode(hex_decode(wire.frame_hex)) verifies and round-trips
   ASSERT chunk_count(frame, wire.mtu_example.mtu) == wire.mtu_example.chunk_count

6. pipeline   (capstone — convergence using ONLY framed bytes)
   (pub,priv) = keypair_from_seed(hex_decode(pipeline.signer_seed_hex))
   att = sign_attest(attest(pipeline.attestation...), priv, pub)
   hop(x,mtu) = decode_stream(reassemble(chunks(encode(x), mtu)))  // bytes only
   w1 = ingest_signed(new_node("W1",["P"]), hop(att, pipeline.mtu_a))
   held = held_attestations(w1,"P")[0]
   w2 = ingest_signed(new_node("W2",["P"]), hop(held, pipeline.mtu_b))
   ASSERT witnessed_rank({w1,w2},["W1","W2"],"P") == pipeline.final_witnessed_rank  # 51.5
   forged = decode(encode(att with delta:=99.0))
   ASSERT verified?(forged) == pipeline.forged_verified                            # false

7. adversarial   (the security boundary)
   h = sign(attest(1,"P",1.5))  by seed adversarial.honest_signer_seed_hex
   c = sign(attest(2,"P",50.0)) by seed adversarial.collude_signer_seed_hex
   5 witnesses; k of them also ingest c (a validly-signed inflated fact):
   ASSERT witnessed_rank(2-of-5 colluded) == adversarial.collusion_minority_2of5  # 51.5 (unmoved)
   ASSERT witnessed_rank(3-of-5 colluded) == adversarial.collusion_majority_3of5  # 100.0 (moved — stated limit)
   m = decode(encode( decode(encode(h)) with delta:=9.9 ))   # byzantine relay
   ASSERT verified?(m) == adversarial.byzantine_relay_delivered                   # false (integrity holds)

PASS iff every assertion holds; exit non-zero on the first failure.
```

See `PROTOCOL_CHANGELOG.md` for the v1→v5 lineage &amp; compatibility rules
(and the two version namespaces: conformance `version` vs wire frame byte).

### Wire frame (normative — big-endian)

```
"FU"      2  magic
0x02      1  version (protocol v2 — frame ver, not the conformance-doc ver)
type      1  0x01 = signed attestation
len       4  u32, payload byte length, MUST be <= 4096
payload  len
digest    4  first 4 bytes of SHA-256(payload)   # transit corruption only

payload = match(u32) | delta_milli(i32) | player_len(u16) | player
        | author_pub(32) | sig(64) | wit_count(u16) | [wlen(u16)|witness]*
```

Codec ≠ crypto: the digest catches bit-rot; `verified?` (Ed25519) is what
authenticates. `:incomplete` means "buffer more and retry" (stream/MTU);
`:oversize`/`:corrupt`/`:bad_frame`/`:version` are hard rejects.

## CI gate

The harness is **the** acceptance test, not a courtesy. Wire it into the
runtime's CI: a normative change bumps `version`; the runtime declares the
version it targets and the harness refuses any mismatch (step 0). No green
harness ⇒ not a Football United node.

## Constants (frozen, from the reference)

| name | value |
|---|---|
| window `W` (pending kept per player) | 8 |
| stranger TTL (idle ticks) | 4 |
| acquaintance threshold (encounters) | 3 |
| acquaintance decay (idle ticks) | 6 |
| rank band / start | [30.0, 100.0] / 50.0 |
| address length (hex chars) | 16 |
| delta scale | ×1000, round-half-away-from-zero |
| wire magic / frame version | `FU` / `0x02` |
| max payload | 4096 bytes |
| frame digest | SHA-256(payload)[0..4] |
