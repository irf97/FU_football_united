"""Conformance harness — runs all 7 sections against vectors.json.

Per ../../redefinition/SECOND_IMPLEMENTATION.md: every mismatch is logged
with expected, actual, the spec source used, and a cause class
(impl_bug | spec_ambiguity | dependency_mismatch | vector_suspicion).
Nothing patches the spec silently; F-tagged items are in DIVERGENCE_LOG.md.
"""
import json
import os
from dataclasses import dataclass, field
from typing import Any, List

from .canonical import canonical
from .identity import Identity, verify
from .mesh import (Node, ingest, ingest_signed, provisional_witnesses,
                   recoverable_rank, witnessed_rank)
from .wire import Attestation, chunk_count, chunks, decode, encode

VECTORS = os.path.join(os.path.dirname(__file__), "..", "..", "..",
                       "fu", "conformance", "vectors.json")


@dataclass
class Result:
    section: str
    key: str
    expected: Any
    actual: Any
    ok: bool
    source: str
    cause: str = ""  # only when not ok


@dataclass
class Report:
    results: List[Result] = field(default_factory=list)

    def check(self, section, key, expected, actual, source, cause="impl_bug"):
        ok = expected == actual
        self.results.append(Result(section, key, expected, actual, ok, source,
                                    "" if ok else cause))
        return ok

    @property
    def passed(self):
        return all(r.ok for r in self.results)

    def summary(self):
        by = {}
        for r in self.results:
            s = by.setdefault(r.section, [0, 0])
            s[0] += 1
            s[1] += 1 if r.ok else 0
        return by


def _signed(idn: Identity, match, player, delta, witnesses=None):
    a = Attestation(match, player, delta, list(witnesses or []), idn.public, b"")
    a.sig = idn.sign(a.canonical_bytes())
    return a


def run(vectors_path: str = VECTORS) -> Report:
    with open(vectors_path, "r", encoding="utf-8") as f:
        doc = json.load(f)
    r = Report()

    # step 0
    r.check("meta", "spec", "fu-mesh-conformance", doc.get("spec"), "README step0")
    r.check("meta", "version", 6, doc.get("version"), "README step0")

    # 1 — identity
    id0 = None
    for i, v in enumerate(doc["identity"]):
        idn = Identity.from_seed_hex(v["seed_hex"])
        if i == 0:
            id0 = idn
        r.check("identity", f"[{i}].public_hex", v["public_hex"], idn.public_hex(), "P3.2")
        r.check("identity", f"[{i}].address", v["address"], idn.address(), "P3.3")
        if "sign_payload" in v:
            sig = idn.sign(v["sign_payload"].encode("utf-8")).hex()
            r.check("identity", f"[{i}].signature_hex", v["signature_hex"], sig, "P3.1")

    # 2 — canonical_attestations
    for j, c in enumerate(doc["canonical_attestations"]):
        cb = canonical(c["match"], c["player"], c["delta"])
        r.check("canonical", f"[{j}].canonical", c["canonical"], cb.decode(), "P4.1/4.2")
        r.check("canonical", f"[{j}].signature_hex", c["signature_hex"],
                id0.sign(cb).hex(), "P4.1")

    # 3 — mesh.signed_ingest  (F3: README ingests w1 only; vector 51.5
    # forces both witnesses to hold the fact — documented choice)
    si = doc["mesh"]["signed_ingest"]
    att = _signed(id0, 1, "p", 1.5, [])
    w1, w2 = Node("w1", ["p"]), Node("w2", ["p"])
    ingest_signed(w1, att)
    ingest_signed(w2, att)  # F3 documented interpretation
    r.check("signed_ingest", "valid_att_rank", si["valid_att_rank"], w1.rank("p"), "P5.1/5.4")
    forged = Attestation(att.match, att.player, 99.0, [], att.author_pub, att.sig)
    w3 = Node("w3", ["p"])
    ingest_signed(w3, forged)
    r.check("signed_ingest", "forged_att_known", si["forged_att_known"],
            w3.knows("p"), "P5.2")
    r.check("signed_ingest", "witnessed_rank_friends", si["witnessed_rank_friends"],
            witnessed_rank({"w1": w1, "w2": w2}, ["w1", "w2"], "p"), "P8.1 (F3)")

    # 4 — bootstrap  (v6: F4 RESOLVED. The scenario is now PINNED in the
    # contract — bootstrap.scenario — and built deterministically from it,
    # exactly as conformance/README.md step 4 prescribes. No invention.
    # The fold is UNSIGNED (scenario.attestation.signed == false).)
    bs = doc["bootstrap"]
    sc = bs["scenario"]
    subj = sc["subject"]
    at = sc["attestation"]
    threshold = sc["acq_threshold"]
    boot_att = Attestation(at["match"], at["player"], at["delta"],
                           at.get("witnesses") or [])  # unsigned: sig stays b""
    nodes = {}
    for nd in sc["nodes"]:
        n = Node(nd["id"], nd.get("friends") or [])
        for _ in range(nd["encounters_with_subject"]):
            n.met(subj)
        if nd["ingests_attestation"]:
            ingest(n, boot_att)  # unsigned fold (P9 bootstrap path)
        nodes[nd["id"]] = n
    pw = sorted(provisional_witnesses(nodes, subj, threshold))
    r.check("bootstrap", "provisional_witnesses", bs["provisional_witnesses"], pw,
            "README step4 / P9.1 (v6 pinned scenario)")
    r.check("bootstrap", "recoverable_rank_no_friends", bs["recoverable_rank_no_friends"],
            recoverable_rank(nodes, sc.get("friend_witnesses") or [], subj, threshold),
            "README step4 / P9.2 (v6 pinned scenario)")
    r.check("bootstrap", "self_excluded", bs["self_excluded"],
            subj not in pw, "P9.1")

    # 5 — wire
    w = doc["wire"]
    wid = Identity.from_seed_hex(w["signer_seed_hex"])
    watt = _signed(wid, w["attestation"]["match"], w["attestation"]["player"],
                    w["attestation"]["delta"], w["attestation"]["witnesses"])
    frame = encode(watt)
    r.check("wire", "frame_hex", w["frame_hex"], frame.hex(), "P9.5.3")
    r.check("wire", "frame_bytes", w["frame_bytes"], len(frame), "P9.5.3")
    dec, leftover = decode(bytes.fromhex(w["frame_hex"]))
    rt_ok = (leftover == b"" and verify(dec.author_pub, dec.canonical_bytes(), dec.sig))
    r.check("wire", "decode_roundtrip_verifies", True, rt_ok, "P9.5.4")
    me = w["mtu_example"]
    r.check("wire", "mtu_chunk_count", me["chunk_count"],
            chunk_count(frame, me["mtu"]), "P9.5.3")
    r.check("wire", "max_payload", w["max_payload"], 4096, "P9.5.1")

    # 6 — pipeline (byte-only relay)
    p = doc["pipeline"]
    pid = Identity.from_seed_hex(p["signer_seed_hex"])
    pa = p["attestation"]
    patt = _signed(pid, pa["match"], pa["player"], pa["delta"], pa["witnesses"])

    def hop(a, mtu):
        return decode(b"".join(chunks(encode(a), mtu)))[0]

    W1 = Node("W1", ["P"])
    ingest_signed(W1, hop(patt, p["mtu_a"]))
    held = W1.held_attestations("P")[0]
    W2 = Node("W2", ["P"])
    ingest_signed(W2, hop(held, p["mtu_b"]))
    r.check("pipeline", "final_witnessed_rank", p["final_witnessed_rank"],
            witnessed_rank({"W1": W1, "W2": W2}, ["W1", "W2"], "P"), "P9.6.1")
    fdelta = Attestation(patt.match, patt.player, 99.0, patt.witnesses,
                         patt.author_pub, patt.sig)
    fdec, _ = decode(encode(fdelta))
    r.check("pipeline", "forged_verified", p["forged_verified"],
            verify(fdec.author_pub, fdec.canonical_bytes(), fdec.sig), "P9.6.2")

    # 7 — adversarial
    a = doc["adversarial"]
    hon = Identity.from_seed_hex(a["honest_signer_seed_hex"])
    col = Identity.from_seed_hex(a["collude_signer_seed_hex"])
    h = _signed(hon, 1, "P", 1.5, [])
    c = _signed(col, 2, "P", 50.0, [])

    def colluded_rank(k):
        nodes = {f"w{i}": Node(f"w{i}") for i in range(5)}
        for i in range(5):
            ingest_signed(nodes[f"w{i}"], h)
            if i < k:
                ingest_signed(nodes[f"w{i}"], c)
        return witnessed_rank(nodes, [f"w{i}" for i in range(5)], "P")

    r.check("adversarial", "collusion_minority_2of5", a["collusion_minority_2of5"],
            colluded_rank(2), "P9.7.1")
    r.check("adversarial", "collusion_majority_3of5", a["collusion_majority_3of5"],
            colluded_rank(3), "P9.7.2")
    relayed, _ = decode(encode(h))
    relayed.delta = 9.9  # byzantine in-transit mutation
    mangled, _ = decode(encode(relayed))
    delivered = verify(mangled.author_pub, mangled.canonical_bytes(), mangled.sig)
    r.check("adversarial", "byzantine_relay_delivered",
            a["byzantine_relay_delivered"], delivered, "P9.7.3")

    return r


if __name__ == "__main__":
    rep = run()
    for r in rep.results:
        mark = "PASS" if r.ok else "FAIL"
        line = f"[{mark}] {r.section}.{r.key}  ({r.source})"
        if not r.ok:
            line += f"\n        expected={r.expected!r} actual={r.actual!r} cause={r.cause}"
        print(line)
    print("\nSUMMARY", {k: f"{v[1]}/{v[0]}" for k, v in rep.summary().items()})
    print("OVERALL", "PASS" if rep.passed else "FAIL")
    raise SystemExit(0 if rep.passed else 1)
