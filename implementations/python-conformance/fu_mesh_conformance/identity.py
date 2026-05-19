"""Identity — fu-protocol.html §3, conformance/README.md.

P3.2 says only "derive deterministically from a 32-byte seed; same seed
=> same public key". It does NOT state the seed *is* the RFC 8032
private key (vs. a hash/KDF of it). See DIVERGENCE_LOG F1: the only
reading consistent with the identity vector (seed 01*32 ->
8a88e3dd...) is "seed == RFC 8032 private key", which is also the
standard RFC 8032 test value — so the vector resolves the prose gap.
"""
import hashlib

from . import _ed25519


class Identity:
    def __init__(self, seed: bytes):
        if len(seed) != 32:
            raise ValueError("seed must be 32 bytes")
        self.seed = seed
        self.public = _ed25519.public_key(seed)  # 32 bytes

    @classmethod
    def from_seed_hex(cls, seed_hex: str) -> "Identity":
        return cls(bytes.fromhex(seed_hex))

    def public_hex(self) -> str:
        return self.public.hex()

    def address(self) -> str:
        # P3.3: lower_hex(SHA-256(public_key))[0..16]
        return hashlib.sha256(self.public).hexdigest()[:16]

    def sign(self, msg: bytes) -> bytes:
        return _ed25519.sign(self.seed, msg)


def verify(public: bytes, msg: bytes, sig: bytes) -> bool:
    return _ed25519.verify(public, msg, sig)
