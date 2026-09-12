"""
NEURONIX Cryptographic Primitives Module (RFC 8032 Ed25519).
Provides pure-Python, zero-dependency Ed25519 digital signature generation,
verification, and canonical payload authentication.

Copyright (c) 2026 NEURONIX Contributors
Licensed under the Apache License, Version 2.0
"""

from __future__ import annotations

import hashlib
import os
from typing import Any, Optional, Tuple

from neuronix_core.state import canonical_json_bytes

# ------------------------------------------------------------------------------
# RFC 8032 Pure-Python Ed25519 Cryptographic Parameters & Arithmetic
# ------------------------------------------------------------------------------
_ED25519_Q = 2**255 - 19
_ED25519_L = 2**252 + 27742317777372353535851937790883648493
_ED25519_D = -121665 * pow(121666, _ED25519_Q - 2, _ED25519_Q) % _ED25519_Q
_ED25519_I = pow(2, (_ED25519_Q - 1) // 4, _ED25519_Q)


def _ed25519_inv(x: int) -> int:
    return pow(x, _ED25519_Q - 2, _ED25519_Q)


def _ed25519_xrecover(y: int) -> int:
    xx = (y * y - 1) * _ed25519_inv(_ED25519_D * y * y + 1)
    x = pow(xx, (_ED25519_Q + 3) // 8, _ED25519_Q)
    if (x * x - xx) % _ED25519_Q != 0:
        x = (x * _ED25519_I) % _ED25519_Q
    if x % 2 != 0:
        x = _ED25519_Q - x
    return x


_ED25519_BY = 4 * _ed25519_inv(5) % _ED25519_Q
_ED25519_BX = _ed25519_xrecover(_ED25519_BY)
_ED25519_B = (_ED25519_BX, _ED25519_BY)


def _ed25519_edwards_add(P: Tuple[int, int], Q: Tuple[int, int]) -> Tuple[int, int]:
    x1, y1 = P
    x2, y2 = Q
    x3 = (x1 * y2 + x2 * y1) * _ed25519_inv(1 + _ED25519_D * x1 * x2 * y1 * y2) % _ED25519_Q
    y3 = (y1 * y2 + x1 * x2) * _ed25519_inv(1 - _ED25519_D * x1 * x2 * y1 * y2) % _ED25519_Q
    return (x3, y3)


def _ed25519_scalarmult(P: Tuple[int, int], e: int) -> Tuple[int, int]:
    if e == 0:
        return (0, 1)
    Q = _ed25519_scalarmult(P, e // 2)
    Q = _ed25519_edwards_add(Q, Q)
    if e & 1:
        Q = _ed25519_edwards_add(Q, P)
    return Q


def _ed25519_encodepoint(P: Tuple[int, int]) -> bytes:
    x, y = P
    b = bytearray(y.to_bytes(32, "little"))
    b[31] |= (x & 1) << 7
    return bytes(b)


def _ed25519_decodepoint(b: bytes) -> Optional[Tuple[int, int]]:
    """Decodes 32-byte string to Edwards curve point adhering to RFC 8032 Section 5.1.3.
    Rejects noncanonical encodings (y >= p), off-curve points, and invalid sign parity."""
    if len(b) != 32:
        return None
    y = int.from_bytes(b[:31] + bytes([b[31] & 0x7F]), "little")
    if y >= _ED25519_Q:
        return None
    u = (y * y - 1) % _ED25519_Q
    v = (_ED25519_D * y * y + 1) % _ED25519_Q
    xx = (u * _ed25519_inv(v)) % _ED25519_Q
    x = pow(xx, (_ED25519_Q + 3) // 8, _ED25519_Q)
    if (x * x - xx) % _ED25519_Q != 0:
        x = (x * _ED25519_I) % _ED25519_Q
    if (x * x - xx) % _ED25519_Q != 0:
        return None
    if x == 0 and ((b[31] >> 7) & 1) == 1:
        return None
    if (x & 1) != ((b[31] >> 7) & 1):
        x = _ED25519_Q - x
    return (x, y)


def _ed25519_publickey(sk: bytes) -> bytes:
    h = hashlib.sha512(sk).digest()
    a = 2**254 + (int.from_bytes(h[:32], "little") & (2**254 - 8))
    A = _ed25519_scalarmult(_ED25519_B, a)
    return _ed25519_encodepoint(A)


def _ed25519_sign(m: bytes, sk: bytes, pk: bytes) -> bytes:
    h = hashlib.sha512(sk).digest()
    a = 2**254 + (int.from_bytes(h[:32], "little") & (2**254 - 8))
    r = int.from_bytes(hashlib.sha512(h[32:] + m).digest(), "little") % _ED25519_L
    R = _ed25519_scalarmult(_ED25519_B, r)
    k = int.from_bytes(hashlib.sha512(_ed25519_encodepoint(R) + pk + m).digest(), "little") % _ED25519_L
    S = (r + k * a) % _ED25519_L
    return _ed25519_encodepoint(R) + S.to_bytes(32, "little")


def _ed25519_verify(s: bytes, m: bytes, pk: bytes) -> bool:
    if len(s) != 64 or len(pk) != 32:
        return False
    try:
        R = _ed25519_decodepoint(s[:32])
        A = _ed25519_decodepoint(pk)
        if R is None or A is None:
            return False
        S = int.from_bytes(s[32:], "little")
        if S >= _ED25519_L:
            return False
        k = int.from_bytes(hashlib.sha512(s[:32] + pk + m).digest(), "little") % _ED25519_L
        v1 = _ed25519_scalarmult(_ED25519_B, S)
        v2 = _ed25519_edwards_add(R, _ed25519_scalarmult(A, k))
        return v1 == v2
    except Exception:
        return False


def generate_keypair() -> Tuple[str, str]:
    """Generates an authentic Ed25519 keypair returning (private_key_hex, public_key_hex)."""
    sk = os.urandom(32)
    pk = _ed25519_publickey(sk)
    return sk.hex(), pk.hex()


def sign_canonical(payload: Any, private_key_hex: str) -> str:
    """Signs canonical RFC 8785 JSON bytes of a payload using Ed25519, returning signature hex."""
    sk = bytes.fromhex(private_key_hex)
    pk = _ed25519_publickey(sk)
    msg_bytes = canonical_json_bytes(payload)
    sig_bytes = _ed25519_sign(msg_bytes, sk, pk)
    return sig_bytes.hex()


def sign_bytes(message: bytes, private_key_hex: str) -> str:
    """Signs raw bytes using Ed25519, returning signature hex."""
    sk = bytes.fromhex(private_key_hex)
    pk = _ed25519_publickey(sk)
    sig_bytes = _ed25519_sign(message, sk, pk)
    return sig_bytes.hex()


def verify_canonical(payload: Any, signature_hex: str, public_key_hex: str) -> bool:
    """Verifies Ed25519 signature over canonical RFC 8785 JSON bytes of a payload."""
    try:
        sig_bytes = bytes.fromhex(signature_hex)
        pk_bytes = bytes.fromhex(public_key_hex)
        msg_bytes = canonical_json_bytes(payload)
        return _ed25519_verify(sig_bytes, msg_bytes, pk_bytes)
    except Exception:
        return False


def verify_bytes(message: bytes, signature_hex: str, public_key_hex: str) -> bool:
    """Verifies Ed25519 signature over raw bytes."""
    try:
        sig_bytes = bytes.fromhex(signature_hex)
        pk_bytes = bytes.fromhex(public_key_hex)
        return _ed25519_verify(sig_bytes, message, pk_bytes)
    except Exception:
        return False

