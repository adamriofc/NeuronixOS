"""
Unit and RFC 8032 Conformance Tests for NEURONIX Cryptographic Primitives.
Validates Ed25519 digital signature generation, verification, known-answer vectors,
malformed input resilience, and canonical payload authentication.
"""

from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT / "packages" / "neuronix-core"))

from neuronix_core.crypto import (
    _ed25519_publickey,
    _ed25519_sign,
    _ed25519_verify,
    generate_keypair,
    sign_canonical,
    verify_canonical,
)


class TestCryptoVectors(unittest.TestCase):
    """Exhaustive cryptographic test vectors for Ed25519 and canonical signing."""

    def test_rfc8032_vector_1(self) -> None:
        """RFC 8032 Test Vector 1: Empty message signature verification."""
        sk = bytes.fromhex(
            "9d61b19deffd5a60ba844af492ec2cc4"
            "4449c5697b326919703bac031cae7f60"
        )
        expected_pk = bytes.fromhex(
            "d75a980182b10ab7d54bfed3c964073a"
            "0ee172f3daa62325af021a68f707511a"
        )
        m = b""
        expected_sig = bytes.fromhex(
            "e5564300c360ac729086e2cc806e828a"
            "84877f1eb8e5d974d873e06522490155"
            "5fb8821590a33bacc61e39701cf9b46b"
            "d25bf5f0595bbe24655141438e7a100b"
        )

        derived_pk = _ed25519_publickey(sk)
        self.assertEqual(derived_pk, expected_pk)

        sig = _ed25519_sign(m, sk, derived_pk)
        self.assertEqual(sig, expected_sig)
        self.assertTrue(_ed25519_verify(sig, m, derived_pk))

    def test_rfc8032_vector_2(self) -> None:
        """RFC 8032 Test Vector 2: 1-byte message signature verification."""
        sk = bytes.fromhex(
            "4ccd089b28ff96da9db6c346ec114e0f"
            "5b8a319f35aba624da8cf6ed4fb8a6fb"
        )
        expected_pk = bytes.fromhex(
            "3d4017c3e843895a92b70aa74d1b7ebc"
            "9c982ccf2ec4968cc0cd55f12af4660c"
        )
        m = bytes.fromhex("72")
        expected_sig = bytes.fromhex(
            "92a009a9f0d4cab8720e820b5f642540"
            "a2b27b5416503f8fb3762223ebdb69da"
            "085ac1e43e15996e458f3613d0f11d8c"
            "387b2eaeb4302aeeb00d291612bb0c00"
        )

        derived_pk = _ed25519_publickey(sk)
        self.assertEqual(derived_pk, expected_pk)

        sig = _ed25519_sign(m, sk, derived_pk)
        self.assertEqual(sig, expected_sig)
        self.assertTrue(_ed25519_verify(sig, m, derived_pk))

    def test_rfc8032_vector_3(self) -> None:
        """RFC 8032 Test Vector 3: 2-byte message signature verification."""
        sk = bytes.fromhex(
            "c5aa8df43f9f837bedb7442f31dcb7b1"
            "66d38535076f094b85ce3a2e0b4458f7"
        )
        expected_pk = bytes.fromhex(
            "fc51cd8e6218a1a38da47ed00230f058"
            "0816ed13ba3303ac5deb911548908025"
        )
        m = bytes.fromhex("af82")
        expected_sig = bytes.fromhex(
            "6291d657deec24024827e69c3abe01a3"
            "0ce548a284743a445e3680d7db5ac3ac"
            "18ff9b538d16f290ae67f760984dc659"
            "4a7c15e9716ed28dc027beceea1ec40a"
        )

        derived_pk = _ed25519_publickey(sk)
        self.assertEqual(derived_pk, expected_pk)

        sig = _ed25519_sign(m, sk, derived_pk)
        self.assertEqual(sig, expected_sig)
        self.assertTrue(_ed25519_verify(sig, m, derived_pk))

    def test_negative_mutated_signature_rejected(self) -> None:
        """Mutating even one bit of the signature invalidates verification."""
        sk, pk = generate_keypair()
        msg = b"System operational state commit 0x1234"
        sig = _ed25519_sign(msg, bytes.fromhex(sk), bytes.fromhex(pk))

        # Bit flip in signature
        mutated_sig = bytearray(sig)
        mutated_sig[0] ^= 0x01
        self.assertFalse(_ed25519_verify(bytes(mutated_sig), msg, bytes.fromhex(pk)))

        mutated_sig_tail = bytearray(sig)
        mutated_sig_tail[63] ^= 0x80
        self.assertFalse(_ed25519_verify(bytes(mutated_sig_tail), msg, bytes.fromhex(pk)))

    def test_negative_mutated_message_rejected(self) -> None:
        """Signature over modified message must fail verification."""
        sk, pk = generate_keypair()
        msg = b"Approved transaction token: 998877"
        sig = _ed25519_sign(msg, bytes.fromhex(sk), bytes.fromhex(pk))

        tampered_msg = b"Approved transaction token: 998878"
        self.assertFalse(_ed25519_verify(sig, tampered_msg, bytes.fromhex(pk)))

    def test_negative_wrong_public_key_rejected(self) -> None:
        """Valid signature verified against an unrelated public key must fail."""
        sk1, pk1 = generate_keypair()
        _, pk2 = generate_keypair()
        msg = b"Deterministic execution receipt"
        sig = _ed25519_sign(msg, bytes.fromhex(sk1), bytes.fromhex(pk1))

        self.assertTrue(_ed25519_verify(sig, msg, bytes.fromhex(pk1)))
        self.assertFalse(_ed25519_verify(sig, msg, bytes.fromhex(pk2)))

    def test_negative_malformed_signature_lengths(self) -> None:
        """Verify fails closed on truncated or oversized signatures."""
        _, pk = generate_keypair()
        msg = b"test payload"
        self.assertFalse(_ed25519_verify(b"too_short", msg, bytes.fromhex(pk)))
        self.assertFalse(_ed25519_verify(b"\x00" * 63, msg, bytes.fromhex(pk)))
        self.assertFalse(_ed25519_verify(b"\x00" * 65, msg, bytes.fromhex(pk)))

    def test_negative_malformed_public_keys(self) -> None:
        """Verify fails closed on invalid public key byte lengths."""
        msg = b"test payload"
        valid_sig = b"\x00" * 64
        self.assertFalse(_ed25519_verify(valid_sig, msg, b"short_pk"))
        self.assertFalse(_ed25519_verify(valid_sig, msg, b"\x00" * 31))
        self.assertFalse(_ed25519_verify(valid_sig, msg, b"\x00" * 33))

    def test_canonical_json_signing_and_verification(self) -> None:
        """Validates canonical RFC 8785 JSON payload signing and verification."""
        sk, pk = generate_keypair()
        payload = {
            "version": "1.0.5",
            "state_root": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
            "components": ["conductor", "vital", "conductor_vt", "uef"],
            "active": True,
            "threshold": 0.95,
        }

        sig_hex = sign_canonical(payload, sk)
        self.assertTrue(verify_canonical(payload, sig_hex, pk))

        # Tampered dictionary payload must fail
        tampered_payload = dict(payload)
        tampered_payload["active"] = False
        self.assertFalse(verify_canonical(tampered_payload, sig_hex, pk))

        # Re-ordered dictionary keys must still verify (RFC 8785 canonical ordering invariant)
        reordered_payload = {
            "threshold": 0.95,
            "active": True,
            "components": ["conductor", "vital", "conductor_vt", "uef"],
            "state_root": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
            "version": "1.0.5",
        }
        self.assertTrue(verify_canonical(reordered_payload, sig_hex, pk))


if __name__ == "__main__":
    unittest.main()
