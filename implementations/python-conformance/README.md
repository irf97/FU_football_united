# python-conformance — independent second implementation

A from-spec Python implementation of the FU Mesh protocol kernel, built
to test whether `fu/conformance/vectors.json` is reproducible by code
that never saw the Elixir reference.

## Honesty caveat (read first)

This **does not cross the legitimacy threshold** in
[`../../redefinition/SECOND_IMPLEMENTATION.md`](../../redefinition/SECOND_IMPLEMENTATION.md).
That contract requires a clean-room implementer. The author of this code
(an AI agent instance) had **prior context containing paraphrases of the
reference algorithm**, which the contract explicitly forbids. So this is
honestly scoped as:

> a **spec-sufficiency audit** — "are spec + vectors enough to implement
> from, and where do they fall short?" — *not* an independent legitimacy
> proof.

The crypto layer is the exception and the strongest signal: Ed25519 is
implemented from RFC 8032 in pure Python (`_ed25519.py`), a completely
separate stack from the BEAM's `:crypto`. Reproducing the byte-exact
`frame_hex` and `signature_hex` from that independent path is real
cross-implementation evidence for sections 1/2/5/6/7, because RFC 8032 is
deterministic and was not paraphrased anywhere.

## Allowed inputs used (only these)

`fu-protocol.html` · `fu/conformance/README.md` · `fu/conformance/vectors.json`
· RFC 8032 (Ed25519) · FIPS 180-4 (SHA-256/512). The Elixir reference,
`bench/conformance_vectors.exs`, `fu/test/**`, and the Mesh Lab were not
read.

## Run

```sh
cd implementations/python-conformance
python -m fu_mesh_conformance.harness     # standalone, no deps
pytest                                     # one test per section
```

No third-party dependencies; pure stdlib + vendored RFC 8032.

## Result

All 31 assertions across all 7 sections reproduce the **v6** vectors
value/byte-exact. **F4 is now resolved** at the contract level: `bootstrap`
carries a pinned `scenario`, and this harness builds bootstrap from it
(unsigned fold, exactly as the reference does) — that PASS is now
spec-determined, not invented. Remaining caveat (`DIVERGENCE_LOG.md`):
F3 stays a prose incompleteness the *vector* forces; F1/F7 are
vector-resolved. See the divergence log for the honest scoping.

## Layout

```
fu_mesh_conformance/
  _ed25519.py   RFC 8032, pure Python (cited standard, not the reference)
  canonical.py  §4 canonical encoding + round-half-away-from-zero
  identity.py   §3 keypair_from_seed / address / sign / verify
  wire.py       §9.5 frame codec + MTU chunking + stream decode
  mesh.py       §5/6/8/9 ingest / rank / witnessed_rank / bootstrap
  harness.py    loads vectors.json, runs all 7 sections, logs causes
tests/test_vectors.py   pytest wrapper (CI gate)
DIVERGENCE_LOG.md       findings F1/F3/F4/F7
```
