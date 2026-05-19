"""Mesh node — fu-protocol.html §5/§6/§8/§9, conformance/README.md.

The rank-fold function is NOT stated in the spec (DIVERGENCE_LOG F7).
The only model consistent with every vector
(signed_ingest 51.5 = 50+1.5; adversarial majority 100.0 = clamp(50+1.5+50);
pipeline 51.5) is:

    rank(player) = clamp(50.0 + sum of deltas of distinct accepted
                         match-ids for that player, 30.0, 100.0)

with §5.3 idempotence keyed by match id. Implemented on that basis and
logged, not silently assumed.
"""
from typing import Dict, List

from .identity import verify
from .wire import Attestation

RANK_START = 50.0
RANK_MIN, RANK_MAX = 30.0, 100.0


def _clamp(x: float) -> float:
    return max(RANK_MIN, min(RANK_MAX, x))


class Node:
    def __init__(self, name: str, cares_about: List[str] = None):
        self.name = name
        # P5 store: player -> {match_id -> Attestation}; rank derived.
        self._att: Dict[str, Dict[int, Attestation]] = {}
        self.cares_about = set(cares_about or [])  # F5: §7 relay gate only
        # acquaintance bookkeeping (§6) for the bootstrap path
        self.encounters: Dict[str, int] = {}

    def rank(self, player: str) -> float:
        if player not in self._att:
            return RANK_START  # unknown -> 50.0 (P5.4)
        total = RANK_START + sum(a.delta for a in self._att[player].values())
        return _clamp(total)

    def knows(self, player: str) -> bool:
        return player in self._att

    def held_attestations(self, player: str) -> List[Attestation]:
        return list(self._att.get(player, {}).values())

    def met(self, peer: str) -> None:
        """A proximity encounter (raises closeness). idle stays 0 here —
        the bootstrap scenario pins ticks=0, so no decay applies."""
        self.encounters[peer] = self.encounters.get(peer, 0) + 1


def _fold(node: Node, att: Attestation) -> None:
    bucket = node._att.setdefault(att.player, {})
    if att.match not in bucket:  # P5.3 idempotent by match id
        bucket[att.match] = att


def ingest(node: Node, att: Attestation) -> None:
    """Unsigned fold. The bootstrap path uses this (no signature) — pinned
    explicit by bootstrap.scenario.attestation.signed == false (v6)."""
    _fold(node, att)


def ingest_signed(node: Node, att: Attestation) -> bool:
    """P5.1/5.2: verify Ed25519 over canonical(att) before any effect;
    drop entirely on failure (no fold, no store, no relay)."""
    if not verify(att.author_pub, att.canonical_bytes(), att.sig):
        return False
    _fold(node, att)
    return True


def witnessed_rank(nodes: Dict[str, Node], witness_names: List[str], subject: str) -> float:
    """P8.1/8.3: median of witnesses' local views, subject's own copy
    excluded; median index div(n-1,2) of sorted views; empty -> 50.0."""
    views = [nodes[w].rank(subject) for w in witness_names if w != subject]
    if not views:
        return RANK_START
    views.sort()
    return views[(len(views) - 1) // 2]


# ---- §9 provisional-witness bootstrap -------------------------------------
# P9.1: provisional witness of S = node (!=S) that regards S as a sustained
# acquaintance (§6: encounters >= 3) AND holds S's record.
ACQ_THRESHOLD = 3


def provisional_witnesses(nodes: Dict[str, Node], subject: str,
                          threshold: int = ACQ_THRESHOLD) -> List[str]:
    out = []
    for name, n in nodes.items():
        if name == subject:
            continue
        if n.encounters.get(subject, 0) >= threshold and n.knows(subject):
            out.append(name)
    return out


def recoverable_rank(nodes: Dict[str, Node], friend_witnesses: List[str],
                      subject: str, threshold: int = ACQ_THRESHOLD) -> float:
    """P9.2: use friend-witnesses if any hold the record; else fall back
    to the median over provisional witnesses (still self-excluded)."""
    holding_friends = [w for w in friend_witnesses if w != subject and nodes[w].knows(subject)]
    if holding_friends:
        return witnessed_rank(nodes, holding_friends, subject)
    prov = provisional_witnesses(nodes, subject, threshold)
    return witnessed_rank(nodes, prov, subject)
