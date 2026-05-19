"""Ed25519 — RFC 8032, pure Python.

Provenance: this is the well-known RFC 8032 reference construction
(SHA-512, curve25519 twisted-Edwards). It implements the *cited public
standard* (allowed input per ../../redefinition/SECOND_IMPLEMENTATION.md),
NOT a transliteration of the Elixir reference, which was never read.

Deliberately chosen over a libsodium/OpenSSL binding: a correct RFC 8032
implementation MUST produce byte-identical signatures for the same key
and message, so reproducing the reference's signatures from an entirely
separate codebase is the actual cross-check.
"""
import hashlib
import sys

sys.setrecursionlimit(4000)

_p = 2 ** 255 - 19
_L = 2 ** 252 + 27742317777372353535851937790883648493  # group order


def _sha512(b: bytes) -> bytes:
    return hashlib.sha512(b).digest()


def _inv(x: int) -> int:
    return pow(x, _p - 2, _p)


_d = (-121665 * _inv(121666)) % _p
_I = pow(2, (_p - 1) // 4, _p)


def _xrecover(y: int) -> int:
    xx = (y * y - 1) * _inv(_d * y * y + 1) % _p
    x = pow(xx, (_p + 3) // 8, _p)
    if (x * x - xx) % _p != 0:
        x = (x * _I) % _p
    if x % 2 != 0:
        x = _p - x
    return x


_By = 4 * _inv(5) % _p
_Bx = _xrecover(_By)
_B = (_Bx % _p, _By % _p)


def _edwards(P, Q):
    x1, y1 = P
    x2, y2 = Q
    k = _d * x1 * x2 * y1 * y2
    x3 = (x1 * y2 + x2 * y1) * _inv(1 + k) % _p
    y3 = (y1 * y2 + x1 * x2) * _inv(1 - k) % _p
    return (x3 % _p, y3 % _p)


def _scalarmult(P, e: int):
    if e == 0:
        return (0, 1)
    Q = _scalarmult(P, e // 2)
    Q = _edwards(Q, Q)
    if e & 1:
        Q = _edwards(Q, P)
    return Q


def _bit(h: bytes, i: int) -> int:
    return (h[i // 8] >> (i % 8)) & 1


def _encodepoint(P) -> bytes:
    x, y = P
    return (y | ((x & 1) << 255)).to_bytes(32, "little")


def _decodepoint(s: bytes):
    y = int.from_bytes(s, "little") & ((1 << 255) - 1)
    x = _xrecover(y)
    if (x & 1) != _bit(s, 255):
        x = _p - x
    P = (x, y)
    if (-x * x + y * y - 1 - _d * x * x * y * y) % _p != 0:
        raise ValueError("point not on curve")
    return P


def _secret_scalar(seed: bytes) -> int:
    h = _sha512(seed)
    return 2 ** 254 + sum(2 ** i * _bit(h, i) for i in range(3, 254))


def _Hint(m: bytes) -> int:
    return int.from_bytes(_sha512(m), "little")


def public_key(seed: bytes) -> bytes:
    """RFC 8032: the 32-byte seed IS the private key; public = [a]B."""
    if len(seed) != 32:
        raise ValueError("seed must be 32 bytes")
    return _encodepoint(_scalarmult(_B, _secret_scalar(seed)))


def sign(seed: bytes, msg: bytes) -> bytes:
    h = _sha512(seed)
    a = 2 ** 254 + sum(2 ** i * _bit(h, i) for i in range(3, 254))
    pub = _encodepoint(_scalarmult(_B, a))
    r = _Hint(h[32:64] + msg)
    R = _scalarmult(_B, r)
    S = (r + _Hint(_encodepoint(R) + pub + msg) * a) % _L
    return _encodepoint(R) + S.to_bytes(32, "little")


def verify(public: bytes, msg: bytes, sig: bytes) -> bool:
    if len(sig) != 64 or len(public) != 32:
        return False
    try:
        R = _decodepoint(sig[:32])
        A = _decodepoint(public)
    except ValueError:
        return False
    S = int.from_bytes(sig[32:], "little")
    if S >= _L:
        return False
    h = _Hint(sig[:32] + public + msg)
    return _scalarmult(_B, S) == _edwards(R, _scalarmult(A, h))
