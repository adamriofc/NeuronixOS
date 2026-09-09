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

# Ensure neuronix-core is in python path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "packages", "neuronix-core")))

from neuronix_core.storage_planner import StoragePlannerEngine, StorageFirewall, DEFAULT_BTRFS_LAYOUT


class TestStoragePlanner(unittest.TestCase):

    def setUp(self):
        self.planner = StoragePlannerEngine()

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
        self.assertEqual(sim["simulation_mode"], "IN_MEMORY_PREFLIGHT")
        self.assertEqual(sim["steps_simulated"], 11)

    def test_firewall_factor2_active_mount_lockout(self):
        # Target device has active mount at '/' -> MUST FAIL CLOSED
        active_mounts = [{"device": "/dev/nvme0n1p2", "mountpoint": "/"}]
        allowed, reason, factors = StorageFirewall.evaluate_7_factors(
            target_device="/dev/nvme0n1",
            plan_hash="d021c7e941decc46adb891dbe50b07786ab68739ced55968a5a70a0c3c2a335d",
            expected_plan_hash="d021c7e941decc46adb891dbe50b07786ab68739ced55968a5a70a0c3c2a335d",
            confirmation_token="DESTROY nvme0n1 PLAN d021c7e941decc46",
            operator_signature=True,
            simulated_entropy=True,
            active_mounts_override=active_mounts
        )
        self.assertFalse(allowed, "Formatting active root device must be strictly blocked")
        self.assertIn("Factor 2 failed", reason)
        self.assertFalse(factors["factor_2_mount_state_safe"])

    def test_firewall_factor6_missing_typed_token(self):
        # Target device is unmounted but has data, token is missing/invalid
        allowed, reason, factors = StorageFirewall.evaluate_7_factors(
            target_device="/dev/sdb",
            plan_hash="d021c7e941decc46adb891dbe50b07786ab68739ced55968a5a70a0c3c2a335d",
            expected_plan_hash="d021c7e941decc46adb891dbe50b07786ab68739ced55968a5a70a0c3c2a335d",
            confirmation_token="yes_i_want_to_format",
            operator_signature=True,
            simulated_entropy=True,
            active_mounts_override=[]
        )
        self.assertFalse(allowed, "Missing typed token must fail closed")
        self.assertIn("Factor 6 failed", reason)
        self.assertFalse(factors["factor_6_typed_token_valid"])

    def test_firewall_factor5_plan_hash_mismatch(self):
        # Plan hash does not match expected hash
        allowed, reason, factors = StorageFirewall.evaluate_7_factors(
            target_device="/dev/sdb",
            plan_hash="hash_aaa",
            expected_plan_hash="hash_bbb",
            confirmation_token="DESTROY sdb PLAN hash_aaa",
            operator_signature=True,
            simulated_entropy=False,
            active_mounts_override=[]
        )
        self.assertFalse(allowed, "Plan hash mismatch must fail closed")
        self.assertIn("Factor 5 failed", reason)

    def test_firewall_factor7_operator_flag_missing(self):
        # Operator confirmation omitted
        allowed, reason, factors = StorageFirewall.evaluate_7_factors(
            target_device="/dev/sdb",
            plan_hash="d021c7e941decc46adb891dbe50b07786ab68739ced55968a5a70a0c3c2a335d",
            expected_plan_hash="d021c7e941decc46adb891dbe50b07786ab68739ced55968a5a70a0c3c2a335d",
            confirmation_token="DESTROY sdb PLAN d021c7e941decc46",
            operator_signature=False,
            simulated_entropy=False,
            active_mounts_override=[]
        )
        self.assertFalse(allowed, "Missing operator signature must fail closed")
        self.assertIn("Factor 7 failed", reason)

    def test_firewall_all_7_factors_satisfied(self):
        plan_hash = "d021c7e941decc46adb891dbe50b07786ab68739ced55968a5a70a0c3c2a335d"
        allowed, reason, factors = StorageFirewall.evaluate_7_factors(
            target_device="/dev/sdb",
            plan_hash=plan_hash,
            expected_plan_hash=plan_hash,
            confirmation_token=f"DESTROY sdb PLAN {plan_hash[:16]}",
            operator_signature=True,
            simulated_entropy=True,
            active_mounts_override=[]
        )
        self.assertTrue(allowed, f"Should pass when all factors satisfied, got: {reason}")
        self.assertEqual(reason, "AUTHORIZED_ALL_7_FACTORS_SATISFIED")
        self.assertTrue(all(factors.values()))


if __name__ == "__main__":
    unittest.main()
