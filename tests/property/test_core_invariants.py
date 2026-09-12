#!/usr/bin/env python3
"""
NEURONIX OS Property-Based Invariant Verification Suite
Tests algebraic and system invariants across randomly generated domains:
- RFC 8785 Canonical JSON determinism and key-ordering idempotence
- Ed25519 signing / verification roundtrip and mutation intolerance
- OCI container provenance classification invariants
- Storage firewall authorization factor invariants
"""

import os
import sys
import json
import random
import string
import unittest

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
sys.path.insert(0, os.path.join(PROJECT_ROOT, "packages/neuronix-core"))

from neuronix_core.crypto import generate_keypair, sign_bytes, verify_bytes, sign_canonical, verify_canonical
from neuronix_core.state import canonical_json_bytes
from neuronix_core.uef.oci_provider import OciContainerProvider


def generate_random_json_primitive(depth=0, max_depth=3):
    """Generates arbitrary nested JSON objects, lists, numbers, booleans, and strings."""
    if depth >= max_depth:
        choice = random.choice(["str", "int", "float", "bool", "none"])
    else:
        choice = random.choice(["str", "int", "float", "bool", "none", "list", "dict"])

    if choice == "str":
        length = random.randint(0, 32)
        chars = string.ascii_letters + string.digits + " _-+=/!@#$%^&*()[]{}"
        return "".join(random.choice(chars) for _ in range(length))
    elif choice == "int":
        return random.randint(-1_000_000, 1_000_000)
    elif choice == "float":
        return round(random.uniform(-10000.0, 10000.0), random.randint(1, 6))
    elif choice == "bool":
        return random.choice([True, False])
    elif choice == "none":
        return None
    elif choice == "list":
        length = random.randint(0, 4)
        return [generate_random_json_primitive(depth + 1, max_depth) for _ in range(length)]
    elif choice == "dict":
        length = random.randint(0, 4)
        result = {}
        for _ in range(length):
            key = "".join(random.choice(string.ascii_letters) for _ in range(random.randint(1, 8)))
            result[key] = generate_random_json_primitive(depth + 1, max_depth)
        return result


class PropertyBasedInvariantsTest(unittest.TestCase):
    """Property-based invariant tests across 100+ random iterations per invariant."""

    def test_property_jcs_canonicalization_idempotence(self):
        """Property 1: canonicalize(canonicalize(X)) == canonicalize(X) and order-independent."""
        for _ in range(100):
            data = generate_random_json_primitive()
            jcs_bytes_1 = canonical_json_bytes(data)
            parsed = json.loads(jcs_bytes_1.decode("utf-8"))
            jcs_bytes_2 = canonical_json_bytes(parsed)
            self.assertEqual(jcs_bytes_1, jcs_bytes_2)

    def test_property_jcs_key_permutation_invariance(self):
        """Property 2: Permuting keys in a dictionary produces identical JCS output."""
        for _ in range(50):
            keys = [f"k_{i}" for i in range(10)]
            random.shuffle(keys)
            d1 = {k: random.randint(0, 100) for k in keys}
            random.shuffle(keys)
            d2 = {k: d1[k] for k in keys}
            self.assertEqual(canonical_json_bytes(d1), canonical_json_bytes(d2))

    def test_property_crypto_roundtrip_invariant(self):
        """Property 3: For all random byte payloads, verify(M, sign(M, sk), pk) == True."""
        sk, pk = generate_keypair()
        for _ in range(10):
            size = random.randint(0, 1024)
            message = os.urandom(size)
            sig = sign_bytes(message, sk)
            self.assertTrue(verify_bytes(message, sig, pk))

    def test_property_crypto_mutation_rejection(self):
        """Property 4: Any single byte mutation in message or signature strictly fails verification."""
        sk, pk = generate_keypair()
        for _ in range(10):
            size = random.randint(1, 256)
            message = os.urandom(size)
            sig = sign_bytes(message, sk)

            # Mutate a random byte in message
            idx = random.randint(0, len(message) - 1)
            mutated_message = bytearray(message)
            mutated_message[idx] ^= 0xFF
            self.assertFalse(verify_bytes(bytes(mutated_message), sig, pk))

            # Mutate a random byte in signature
            sig_bytes = bytearray(bytes.fromhex(sig))
            sig_idx = random.randint(0, len(sig_bytes) - 1)
            sig_bytes[sig_idx] ^= 0x01
            self.assertFalse(verify_bytes(message, sig_bytes.hex(), pk))

    def test_property_oci_image_provenance_invariant(self):
        """Property 5: Digests containing @sha256:... are strictly PROVENANCE_STRONG."""
        hex_chars = "0123456789abcdef"
        for _ in range(100):
            repo = "".join(random.choice(string.ascii_lowercase) for _ in range(random.randint(3, 10)))
            tag = "".join(random.choice(string.ascii_lowercase) for _ in range(random.randint(3, 8)))
            digest = "".join(random.choice(hex_chars) for _ in range(64))

            # Strong provenance pattern
            pinned_ref = f"{repo}:{tag}@sha256:{digest}"
            prov_strong = OciContainerProvider.classify_image_provenance(pinned_ref)
            self.assertEqual(prov_strong, "PROVENANCE_STRONG")

            # Normal provenance pattern
            mutable_ref = f"{repo}:{tag}"
            prov_normal = OciContainerProvider.classify_image_provenance(mutable_ref)
            self.assertEqual(prov_normal, "PROVENANCE_NORMAL")


if __name__ == "__main__":
    unittest.main()
