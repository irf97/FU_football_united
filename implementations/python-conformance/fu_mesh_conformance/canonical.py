"""Canonical encoding — fu-protocol.html §4, conformance/README.md.

canonical(att) = "{match}|{player}|{delta_milli}"  (UTF-8)
delta_milli    = round(delta * 1000), round-half-AWAY-from-zero, integer.

Python's builtin round() is round-half-to-EVEN, so it cannot be used.
Decimal ROUND_HALF_UP == "ties away from zero" (incl. negatives) — the
spec's exact rule. Float arithmetic noise (0.1+0.2 -> 0.300000...04)
collapses to the same integer 300 because Decimal(float) takes the exact
binary value and the *1000 scale dominates the noise (pinned by the
canonical_attestations vectors).
"""
from decimal import Decimal, ROUND_HALF_UP


def delta_milli(delta) -> int:
    return int((Decimal(delta) * 1000).quantize(Decimal(1), rounding=ROUND_HALF_UP))


def canonical(match: int, player: str, delta) -> bytes:
    if "|" in player:
        raise ValueError("player MUST NOT contain '|' (P4.4)")
    return f"{match}|{player}|{delta_milli(delta)}".encode("utf-8")
