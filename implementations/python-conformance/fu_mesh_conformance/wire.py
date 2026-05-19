"""Wire framing — fu-protocol.html §9.5, conformance/README.md.

Frame (big-endian):
  "FU"   2  magic
  0x02   1  frame version
  0x01   1  type = signed attestation
  len    4  u32, payload bytes, MUST be <= 4096
  payload len
  digest 4  SHA-256(payload)[0..4]   (transit corruption only; NOT crypto)

payload = match(u32) | delta_milli(i32) | player_len(u16) | player
        | author_pub(32) | sig(64) | wit_count(u16) | [wlen(u16)|witness]*
"""
import hashlib
import struct
from dataclasses import dataclass, field
from typing import List, Optional, Tuple

from .canonical import canonical, delta_milli

MAGIC = b"FU"
FRAME_VERSION = 0x02
TYPE_ATT = 0x01
MAX_PAYLOAD = 4096


@dataclass
class Attestation:
    match: int
    player: str
    delta: float
    witnesses: List[str] = field(default_factory=list)
    author_pub: bytes = b""  # 32
    sig: bytes = b""  # 64

    def canonical_bytes(self) -> bytes:
        return canonical(self.match, self.player, self.delta)


class WireError(Exception):
    def __init__(self, kind: str):
        super().__init__(kind)
        self.kind = kind  # incomplete|oversize|corrupt|version|bad_frame


def encode(att: Attestation) -> bytes:
    player_b = att.player.encode("utf-8")
    dm = delta_milli(att.delta)
    payload = (
        struct.pack(">I", att.match)
        + struct.pack(">i", dm)
        + struct.pack(">H", len(player_b))
        + player_b
        + att.author_pub
        + att.sig
        + struct.pack(">H", len(att.witnesses))
    )
    for w in att.witnesses:
        wb = w.encode("utf-8")
        payload += struct.pack(">H", len(wb)) + wb
    if len(payload) > MAX_PAYLOAD:
        raise WireError("oversize")
    digest = hashlib.sha256(payload).digest()[:4]
    return MAGIC + bytes([FRAME_VERSION, TYPE_ATT]) + struct.pack(">I", len(payload)) + payload + digest


def decode(buf: bytes) -> Tuple[Attestation, bytes]:
    """Returns (att, leftover). Raises WireError(kind) otherwise."""
    if len(buf) < 8:
        raise WireError("incomplete")
    if buf[0:2] != MAGIC:
        raise WireError("bad_frame")
    if buf[2] != FRAME_VERSION:
        raise WireError("version")
    if buf[3] != TYPE_ATT:
        raise WireError("bad_frame")
    (length,) = struct.unpack(">I", buf[4:8])
    if length > MAX_PAYLOAD:
        raise WireError("oversize")
    if len(buf) < 8 + length + 4:
        raise WireError("incomplete")
    payload = buf[8 : 8 + length]
    digest = buf[8 + length : 8 + length + 4]
    leftover = buf[8 + length + 4 :]
    if hashlib.sha256(payload).digest()[:4] != digest:
        raise WireError("corrupt")

    o = 0

    def take(n):
        nonlocal o
        b = payload[o : o + n]
        o += n
        return b

    (match,) = struct.unpack(">I", take(4))
    (dm,) = struct.unpack(">i", take(4))
    (plen,) = struct.unpack(">H", take(2))
    player = take(plen).decode("utf-8")
    author_pub = take(32)
    sig = take(64)
    (wc,) = struct.unpack(">H", take(2))
    witnesses = []
    for _ in range(wc):
        (wl,) = struct.unpack(">H", take(2))
        witnesses.append(take(wl).decode("utf-8"))
    # delta carried on the wire is the integer milli; recover float view.
    att = Attestation(match, player, dm / 1000.0, witnesses, author_pub, sig)
    return att, leftover


def chunks(frame: bytes, mtu: int) -> List[bytes]:
    """Plain <=mtu splits whose concatenation is the original (P9.5.3)."""
    return [frame[i : i + mtu] for i in range(0, len(frame), mtu)]


def chunk_count(frame: bytes, mtu: int) -> int:
    return (len(frame) + mtu - 1) // mtu


def decode_stream(buf: bytes) -> List[Attestation]:
    out, leftover = [], buf
    while leftover:
        try:
            att, leftover = decode(leftover)
            out.append(att)
        except WireError as e:
            if e.kind == "incomplete":
                break
            raise
    return out
