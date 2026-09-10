"""
Unit and Invariant Tests for NEURONIX Storage Planner & 7-Factor Firewall
Validates deterministic storage plan synthesis, preflight simulation,
and fail-closed rejection under active mount and missing token hazards (SEC-012).

Copyright (c) 2026 NEURONIX Contributors
Licensed under the Apache License, Version 2.0
"""

import unittest
import os
import sys
import time

# Ensure neuronix-core is in python path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "packages", "neuronix-core")))

from neuronix_core.storage_planner import (
    StoragePlannerEngine,
    StorageFirewall,
    DEFAULT_BTRFS_LAYOUT,
    generate_operator_keypair,
    sign_storage_authorization,
    verify_storage_authorization
)


class TestStoragePlanner(unittest.TestCase):

    def setUp(self):
        self.planner = StoragePlannerEngine()
        self.op_sk, self.op_pk = generate_operator_keypair()
        self.wrong_sk, self.wrong_pk = generate_operator_keypair()

    def _create_auth(
        self,
        device: str,
        plan_hash: str,
        op_id: str = "secops@neuronix.os",
        clearance: str = "STORAGE_ADMIN",
        nonce: str = "nonce_storage_test_001",
        expiry: int = 0,
        sk_hex: str = ""
    ) -> dict:
        exp = expiry if expiry > 0 else int(time.time()) + 3600
        key = sk_hex if sk_hex else self.op_sk
        return sign_storage_authorization(
            target_device=device,
            plan_hash=plan_hash,
            operator_id=op_id,
            clearance=clearance,
            challenge_nonce=nonce,
            expiry=exp,
            secret_key_hex=key
        )

    def test_deterministic_plan_generation(self):
        plan1 = self.planner.generate_plan()
        plan2 = self.planner.generate_plan()
        hash1 = self.planner.compute_plan_hash(plan1)
        hash2 = self.planner.compute_plan_hash(plan2)

        self.assertEqual(hash1, hash2, "StoragePlanHash must be strictly deterministic")
        self.assertEqual(len(hash1), 64, "Plan hash must be a valid 64-char SHA-256")
        self.assertGreater(plan1["step_count"], 0, "Generated plan must contain steps")

    def test_storage_root_derivation(self):
        root = self.planner.compute_storage_root()
        self.assertEqual(len(root), 64)
        self.assertTrue(all(c in "0123456789abcdef" for c in root))

    def test_preflight_simulation(self):
        sim = self.planner.simulate_execution()
        self.assertTrue(sim["all_steps_succeeded"])
        self.assertEqual(sim["simulation_mode"], "SEMANTIC_PREFLIGHT")
        self.assertEqual(sim["steps_simulated"], 11)
        self.assertEqual(len(sim["errors"]), 0)

    def test_firewall_factor2_active_mount_lockout(self):
        # Target device has active mount at '/' -> MUST FAIL CLOSED
        plan_hash = "d021c7e941decc46adb891dbe50b07786ab68739ced55968a5a70a0c3c2a335d"
        auth = self._create_auth("/dev/nvme0n1", plan_hash, nonce="nonce_factor2")
        active_mounts = [{"device": "/dev/nvme0n1p2", "mountpoint": "/"}]
        allowed, reason, factors = StorageFirewall.evaluate_7_factors(
            target_device="/dev/nvme0n1",
            plan_hash=plan_hash,
            expected_plan_hash=plan_hash,
            confirmation_token=f"DESTROY nvme0n1 PLAN {plan_hash}",
            operator_auth=auth,
            simulated_entropy=True,
            active_mounts_override=active_mounts
        )
        self.assertFalse(allowed, "Formatting active root device must be strictly blocked")
        self.assertIn("Factor 2 failed", reason)
        self.assertFalse(factors["factor_2_mount_state_safe"])

    def test_firewall_factor3_active_generation_safety(self):
        # Target device hosts active NixOS generation -> MUST FAIL CLOSED
        active_devices = {"/dev/sdb", "/dev/sdb1"}
        plan_hash = "d021c7e941decc46adb891dbe50b07786ab68739ced55968a5a70a0c3c2a335d"
        auth = self._create_auth("/dev/sdb", plan_hash, nonce="nonce_factor3")
        allowed, reason, factors = StorageFirewall.evaluate_7_factors(
            target_device="/dev/sdb",
            plan_hash=plan_hash,
            expected_plan_hash=plan_hash,
            confirmation_token=f"DESTROY sdb PLAN {plan_hash}",
            operator_auth=auth,
            simulated_entropy=False,
            active_mounts_override=[],
            active_devices_override=active_devices,
            allow_active_generation_override=False
        )
        self.assertFalse(allowed, "Target device hosting active generation must fail closed")
        self.assertIn("Factor 3 failed", reason)
        self.assertFalse(factors["factor_3_generation_safety"])

    def test_firewall_factor6_missing_or_partial_typed_token(self):
        # Target device has existing data; partial prefix or missing token must fail closed
        plan_hash = "d021c7e941decc46adb891dbe50b07786ab68739ced55968a5a70a0c3c2a335d"
        auth = self._create_auth("/dev/sdb", plan_hash, nonce="nonce_factor6_1")
        # 1. Random string
        allowed, reason, factors = StorageFirewall.evaluate_7_factors(
            target_device="/dev/sdb",
            plan_hash=plan_hash,
            expected_plan_hash=plan_hash,
            confirmation_token="yes_i_want_to_format",
            operator_auth=auth,
            simulated_entropy=True,
            active_mounts_override=[],
            active_devices_override=set()
        )
        self.assertFalse(allowed, "Random string token must fail closed")
        self.assertIn("Factor 6 failed", reason)
        self.assertFalse(factors["factor_6_typed_token_valid"])

        # 2. Partial prefix (must require exact full hash)
        auth2 = self._create_auth("/dev/sdb", plan_hash, nonce="nonce_factor6_2")
        allowed, reason, factors = StorageFirewall.evaluate_7_factors(
            target_device="/dev/sdb",
            plan_hash=plan_hash,
            expected_plan_hash=plan_hash,
            confirmation_token=f"DESTROY sdb PLAN {plan_hash[:16]}",
            operator_auth=auth2,
            simulated_entropy=True,
            active_mounts_override=[],
            active_devices_override=set()
        )
        self.assertFalse(allowed, "Partial prefix token must fail closed; exact hash required")
        self.assertIn("Factor 6 failed", reason)

    def test_firewall_factor5_plan_hash_mismatch(self):
        # Plan hash does not match expected hash
        auth = self._create_auth("/dev/sdb", "hash_aaa", nonce="nonce_factor5")
        allowed, reason, factors = StorageFirewall.evaluate_7_factors(
            target_device="/dev/sdb",
            plan_hash="hash_aaa",
            expected_plan_hash="hash_bbb",
            confirmation_token="DESTROY sdb PLAN hash_aaa",
            operator_auth=auth,
            simulated_entropy=False,
            active_mounts_override=[],
            active_devices_override=set()
        )
        self.assertFalse(allowed, "Plan hash mismatch must fail closed")
        self.assertIn("Factor 5 failed", reason)

    def test_firewall_factor7_operator_auth_rejected(self):
        plan_hash = "d021c7e941decc46adb891dbe50b07786ab68739ced55968a5a70a0c3c2a335d"

        # 1. Plain boolean True (disallowed, requires asymmetric cryptographic authorization)
        allowed, reason, factors = StorageFirewall.evaluate_7_factors(
            target_device="/dev/sdb",
            plan_hash=plan_hash,
            expected_plan_hash=plan_hash,
            confirmation_token=f"DESTROY sdb PLAN {plan_hash}",
            operator_auth=True,
            simulated_entropy=False,
            active_mounts_override=[],
            active_devices_override=set()
        )
        self.assertFalse(allowed, "Plain boolean True without identity must fail closed")
        self.assertIn("Factor 7 failed", reason)

        # 2. Dummy string signature (SEC-012 non-empty string presence bypass)
        dummy_auth = {"operator_id": "admin@sys", "clearance": "STORAGE_ADMIN", "signature": "valid"}
        allowed, reason, factors = StorageFirewall.evaluate_7_factors(
            target_device="/dev/sdb",
            plan_hash=plan_hash,
            expected_plan_hash=plan_hash,
            confirmation_token=f"DESTROY sdb PLAN {plan_hash}",
            operator_auth=dummy_auth,
            simulated_entropy=False,
            active_mounts_override=[],
            active_devices_override=set()
        )
        self.assertFalse(allowed, "Dummy string signature must fail closed")
        self.assertIn("Factor 7 failed", reason)

        # 3. Operator with insufficient clearance (VIEWER)
        auth_bad_clearance = self._create_auth("/dev/sdb", plan_hash, clearance="VIEWER", nonce="nonce_f7_clearance")
        allowed, reason, factors = StorageFirewall.evaluate_7_factors(
            target_device="/dev/sdb",
            plan_hash=plan_hash,
            expected_plan_hash=plan_hash,
            confirmation_token=f"DESTROY sdb PLAN {plan_hash}",
            operator_auth=auth_bad_clearance,
            simulated_entropy=False,
            active_mounts_override=[],
            active_devices_override=set()
        )
        self.assertFalse(allowed, "Insufficient clearance must fail closed")
        self.assertIn("Factor 7 failed", reason)

        # 4. Tampered device in signed payload (signed for /dev/sdc, presented for /dev/sdb)
        auth_diff_device = self._create_auth("/dev/sdc", plan_hash, nonce="nonce_f7_device")
        allowed, reason, factors = StorageFirewall.evaluate_7_factors(
            target_device="/dev/sdb",
            plan_hash=plan_hash,
            expected_plan_hash=plan_hash,
            confirmation_token=f"DESTROY sdb PLAN {plan_hash}",
            operator_auth=auth_diff_device,
            simulated_entropy=False,
            active_mounts_override=[],
            active_devices_override=set()
        )
        self.assertFalse(allowed, "Tampered device must fail closed")
        self.assertIn("Factor 7 failed", reason)

        # 5. Tampered plan hash in signed payload
        auth_diff_plan = self._create_auth("/dev/sdb", "0" * 64, nonce="nonce_f7_plan")
        allowed, reason, factors = StorageFirewall.evaluate_7_factors(
            target_device="/dev/sdb",
            plan_hash=plan_hash,
            expected_plan_hash=plan_hash,
            confirmation_token=f"DESTROY sdb PLAN {plan_hash}",
            operator_auth=auth_diff_plan,
            simulated_entropy=False,
            active_mounts_override=[],
            active_devices_override=set()
        )
        self.assertFalse(allowed, "Tampered plan hash must fail closed")
        self.assertIn("Factor 7 failed", reason)

        # 6. Expired authorization token
        auth_expired = self._create_auth("/dev/sdb", plan_hash, nonce="nonce_f7_expired", expiry=int(time.time()) - 100)
        allowed, reason, factors = StorageFirewall.evaluate_7_factors(
            target_device="/dev/sdb",
            plan_hash=plan_hash,
            expected_plan_hash=plan_hash,
            confirmation_token=f"DESTROY sdb PLAN {plan_hash}",
            operator_auth=auth_expired,
            simulated_entropy=False,
            active_mounts_override=[],
            active_devices_override=set()
        )
        self.assertFalse(allowed, "Expired token must fail closed")
        self.assertIn("Factor 7 failed", reason)
        self.assertIn("EXPIRED_AUTHORIZATION", reason)

        # 7. Replay attack: reusing already consumed challenge nonce
        auth_replay = self._create_auth("/dev/sdb", plan_hash, nonce="nonce_f7_replay_target")
        test_seen_nonces = set()
        ok1, _, _ = StorageFirewall.evaluate_7_factors(
            target_device="/dev/sdb",
            plan_hash=plan_hash,
            expected_plan_hash=plan_hash,
            confirmation_token=f"DESTROY sdb PLAN {plan_hash}",
            operator_auth=auth_replay,
            simulated_entropy=False,
            active_mounts_override=[],
            active_devices_override=set(),
            seen_nonces=test_seen_nonces
        )
        self.assertTrue(ok1, "First evaluation with new nonce must succeed")

        ok2, reason2, _ = StorageFirewall.evaluate_7_factors(
            target_device="/dev/sdb",
            plan_hash=plan_hash,
            expected_plan_hash=plan_hash,
            confirmation_token=f"DESTROY sdb PLAN {plan_hash}",
            operator_auth=auth_replay,
            simulated_entropy=False,
            active_mounts_override=[],
            active_devices_override=set(),
            seen_nonces=test_seen_nonces
        )
        self.assertFalse(ok2, "Replay evaluation with consumed nonce must fail closed")
        self.assertIn("REPLAY_ATTACK_DETECTED", reason2)

        # 8. Untrusted operator public key
        auth_untrusted = self._create_auth("/dev/sdb", plan_hash, nonce="nonce_f7_untrusted", sk_hex=self.wrong_sk)
        allowed, reason, factors = StorageFirewall.evaluate_7_factors(
            target_device="/dev/sdb",
            plan_hash=plan_hash,
            expected_plan_hash=plan_hash,
            confirmation_token=f"DESTROY sdb PLAN {plan_hash}",
            operator_auth=auth_untrusted,
            simulated_entropy=False,
            active_mounts_override=[],
            active_devices_override=set(),
            trusted_public_keys=[self.op_pk]
        )
        self.assertFalse(allowed, "Untrusted public key must fail closed")
        self.assertIn("UNTRUSTED_KEY", reason)

    def test_firewall_all_7_factors_satisfied(self):
        plan_hash = "d021c7e941decc46adb891dbe50b07786ab68739ced55968a5a70a0c3c2a335d"
        auth = self._create_auth("/dev/sdb", plan_hash, op_id="secops@neuronix.os", clearance="STORAGE_ADMIN", nonce="nonce_all_pass")
        allowed, reason, factors = StorageFirewall.evaluate_7_factors(
            target_device="/dev/sdb",
            plan_hash=plan_hash,
            expected_plan_hash=plan_hash,
            confirmation_token=f"DESTROY sdb PLAN {plan_hash}",
            operator_auth=auth,
            simulated_entropy=True,
            active_mounts_override=[],
            active_devices_override=set()
        )
        self.assertTrue(allowed, f"Should pass when all factors satisfied, got: {reason}")
        self.assertEqual(reason, "AUTHORIZED_ALL_7_FACTORS_SATISFIED")
        self.assertTrue(all(factors.values()))

    def test_postcondition_verification(self):
        # Observed state matches plan exactly
        observed_valid = {
            "partitions": [{"name": "ESP"}, {"name": "root"}],
            "btrfs_subvolumes": ["@", "@nix", "@home", "@snapshots", "@swap"]
        }
        ok, msg = self.planner.verify_postconditions(observed_valid)
        self.assertTrue(ok, f"Expected postcondition match, got {msg}")
        self.assertEqual(msg, "POSTCONDITION_VERIFIED_EXACT_MATCH")

        # Observed state has missing partition -> MUST FAIL CLOSED
        observed_invalid = {
            "partitions": [{"name": "ESP"}],
            "btrfs_subvolumes": ["@", "@nix"]
        }
        ok, msg = self.planner.verify_postconditions(observed_invalid)
        self.assertFalse(ok)
        self.assertIn("POSTCONDITION_MISMATCH", msg)


if __name__ == "__main__":
    unittest.main()

