"""
Comprehensive Semantic Closure Verification Suite (MES-NRX-002)
Validates real cryptographic decryption, 7-factor storage firewall,
boot health monotonic state transitions, semantic Nix AST governance,
effective topology convergence, and offline verification passport guarantees.

Copyright (c) 2026 NEURONIX Contributors
Licensed under the Apache License, Version 2.0
"""

import os
import sys
import json
import tempfile
import unittest

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(PROJECT_ROOT, "packages/neuronix-core"))
sys.path.insert(0, os.path.join(PROJECT_ROOT, "tools"))

from neuronix_core.secrets import (
    SecretFabricEngine,
    encrypt_secret_envelope,
    decrypt_secret_envelope,
    is_volatile_ram_filesystem,
)
from neuronix_core.storage_planner import (
    StoragePlannerEngine,
    StorageFirewall,
    get_active_generation_devices,
)
from neuronix_core.boot_trust import (
    CONTRACT_STAGES,
    BootHealthContract,
    MeasuredBootVerifier,
)
from neuronix_core.semantic import (
    SemanticAstEngine,
    SemanticAIGovernor,
    parse_nix_ast,
    CANONICAL_OPTIONS,
)
from neuronix_core.topology import (
    SystemTopologyEngine,
)
from verify_passport import (
    canonical_json_bytes,
    verify_passport,
    verify_release_proof,
    verify_evidence_graph,
    trace_graph_lineage,
)


class TestSecretsSemanticClosure(unittest.TestCase):
    """Verifies Critical #1: Real Age authenticated envelope decryption and RAM safety."""

    def setUp(self):
        self.engine = SecretFabricEngine()
        self.ident = "AGE-SECRET-KEY-1DEMOKEY987654321012345678901234567890123456789012345678"
        self.recipient = SecretFabricEngine.derive_public_key_from_identity(self.ident)

    def test_authenticated_envelope_roundtrip(self):
        payload = "NEURONIX_SUPER_SECRET_PAYLOAD_999"
        ciphertext = encrypt_secret_envelope(
            plaintext=payload,
            recipients=[self.recipient],
            identity_key=self.ident
        )
        data = json.loads(ciphertext)
        self.assertEqual(data.get("format"), "age/v1-authenticated-envelope")
        self.assertIn("mac", data)
        self.assertIn("ciphertext", data)

        ok, msg, decrypted = decrypt_secret_envelope(
            ciphertext_raw=ciphertext,
            identity_key=self.ident,
            allowed_recipients=[self.recipient]
        )
        self.assertTrue(ok, f"Decryption should succeed: {msg}")
        self.assertEqual(decrypted, payload)

    def test_fail_closed_missing_identity(self):
        payload = "CONFIDENTIAL_PAYLOAD"
        ciphertext = encrypt_secret_envelope(
            plaintext=payload,
            recipients=[self.recipient]
        )
        wrong_ident = "AGE-SECRET-KEY-WRONGKEYWRONGKEYWRONGKEYWRONGKEYWRONGKEYWRONGKEYWRONGKEY"
        ok, msg, decrypted = decrypt_secret_envelope(
            ciphertext_raw=ciphertext,
            identity_key=wrong_ident,
            allowed_recipients=[self.recipient]
        )
        self.assertFalse(ok)
        self.assertIn("MISSING_AGE_IDENTITY", msg)
        self.assertIsNone(decrypted)

    def test_fail_closed_tampered_ciphertext(self):
        payload = "CONFIDENTIAL_PAYLOAD"
        ciphertext = encrypt_secret_envelope(
            plaintext=payload,
            recipients=[self.recipient]
        )
        env = json.loads(ciphertext)
        env["mac"] = "0" * 64
        tampered = json.dumps(env)

        ok, msg, decrypted = decrypt_secret_envelope(
            ciphertext_raw=tampered,
            identity_key=self.ident,
            allowed_recipients=[self.recipient]
        )
        self.assertFalse(ok)
        self.assertIn("MAC verification failed", msg)
        self.assertIsNone(decrypted)

    def test_capability_bound_materialization_authorization(self):
        ciphertext = encrypt_secret_envelope("SECRET_DB_PASS", [self.recipient])
        self.engine.register_secret(
            name="db_password",
            ciphertext=ciphertext,
            required_capability="cap:db.read",
            recipients=[self.recipient]
        )
        # Unauthorized capability token
        ok, reason, _ = self.engine.materialize_secret(
            name="db_password",
            capability_token="cap:unrelated.read",
            identity_key=self.ident
        )
        self.assertFalse(ok)
        self.assertIn("CAPABILITY_MISMATCH", reason)

        # Missing identity key
        ok, reason, _ = self.engine.materialize_secret(
            name="db_password",
            capability_token="cap:db.read",
            identity_key=None
        )
        self.assertFalse(ok)
        self.assertIn("MISSING_AGE_IDENTITY", reason)

    def test_volatile_ram_verification(self):
        # /dev/shm and /run are volatile RAM
        self.assertTrue(is_volatile_ram_filesystem("/dev/shm"))
        self.assertTrue(is_volatile_ram_filesystem("/run"))
        # Non-RAM paths fail volatile verification
        self.assertFalse(is_volatile_ram_filesystem("/var/log/nonvolatile"))

    def test_ai_metadata_masking(self):
        ciphertext = encrypt_secret_envelope("SECRET_API_TOKEN", [self.recipient])
        self.engine.register_secret(
            name="api_token",
            ciphertext=ciphertext,
            required_capability="cap:api.call",
            recipients=[self.recipient]
        )
        ai_view = self.engine.filter_secret_for_actor("api_token", actor_role="ai_agent")
        self.assertEqual(ai_view.get("value"), "[MASKED: AI_SECRET_VISIBILITY_METADATA_ONLY]")
        self.assertEqual(ai_view.get("plaintext_visibility"), "METADATA_ONLY")
        self.assertNotIn("SECRET_API_TOKEN", str(ai_view))


class TestStorageFirewallSemanticClosure(unittest.TestCase):
    """Verifies Critical #2: 7-Factor Storage Safety Firewall and Preflight Validation."""

    def setUp(self):
        self.planner = StoragePlannerEngine()
        self.plan = self.planner.generate_plan()
        self.plan_hash = self.planner.compute_plan_hash(self.plan)

    def test_factor3_active_generation_rejection(self):
        # If target device holds active generation, must fail closed
        active_gen_devices = {"/dev/vdz1", "/dev/vdz"}
        allowed, reason, factors = StorageFirewall.evaluate_7_factors(
            target_device="/dev/vdz",
            plan_hash=self.plan_hash,
            expected_plan_hash=self.plan_hash,
            confirmation_token=f"DESTROY vdz PLAN {self.plan_hash}",
            operator_auth={"operator_id": "admin@sys", "clearance": "STORAGE_ADMIN", "signature": "valid"},
            simulated_entropy=True,
            active_mounts_override=[],
            active_devices_override=active_gen_devices
        )
        self.assertFalse(allowed)
        self.assertIn("Factor 3 failed", reason)
        self.assertIn("active nixos generation", reason.lower())

    def test_factor6_strict_confirmation_token(self):
        # Non-exact or invalid confirmation token must fail closed
        bad_token = "DESTROY vdz"
        allowed, reason, factors = StorageFirewall.evaluate_7_factors(
            target_device="/dev/vdz",
            plan_hash=self.plan_hash,
            expected_plan_hash=self.plan_hash,
            confirmation_token=bad_token,
            operator_auth={"operator_id": "admin@sys", "clearance": "STORAGE_ADMIN", "signature": "valid"},
            simulated_entropy=True,
            active_mounts_override=[],
            active_devices_override=set()
        )
        self.assertFalse(allowed)
        self.assertIn("Factor 6 failed", reason)

    def test_factor7_unauthorized_operator(self):
        # Operator without STORAGE_ADMIN clearance must fail closed
        allowed, reason, factors = StorageFirewall.evaluate_7_factors(
            target_device="/dev/vdz",
            plan_hash=self.plan_hash,
            expected_plan_hash=self.plan_hash,
            confirmation_token=f"DESTROY vdz PLAN {self.plan_hash}",
            operator_auth={"operator_id": "guest@sys", "clearance": "AUDITOR", "signature": "valid"},
            simulated_entropy=True,
            active_mounts_override=[],
            active_devices_override=set()
        )
        self.assertFalse(allowed)
        self.assertIn("Factor 7 failed", reason)
        self.assertIn("STORAGE_ADMIN", reason)

    def test_all_7_factors_pass_when_compliant(self):
        allowed, reason, factors = StorageFirewall.evaluate_7_factors(
            target_device="/dev/vdz",
            plan_hash=self.plan_hash,
            expected_plan_hash=self.plan_hash,
            confirmation_token=f"DESTROY vdz PLAN {self.plan_hash}",
            operator_auth={"operator_id": "secops@sys", "clearance": "DISASTER_RECOVERY_OPERATOR", "signature": "valid_sig"},
            simulated_entropy=True,
            active_mounts_override=[],
            active_devices_override=set()
        )
        self.assertTrue(allowed)
        self.assertEqual(len(factors), 7)
        self.assertTrue(all(factors.values()))

    def test_preflight_simulation_and_postconditions(self):
        sim = self.planner.simulate_execution(self.plan)
        self.assertTrue(sim["all_steps_succeeded"])
        self.assertEqual(sim["simulation_mode"], "SEMANTIC_PREFLIGHT")
        self.assertEqual(len(sim["errors"]), 0)

        observed_valid = {
            "partitions": [{"name": "ESP"}, {"name": "root"}],
            "btrfs_subvolumes": ["@", "@nix", "@home", "@snapshots", "@swap"]
        }
        post_ok, post_msg = self.planner.verify_postconditions(observed_valid, self.plan)
        self.assertTrue(post_ok, f"Postconditions should verify: {post_msg}")

        observed_invalid = {"partitions": [{"name": "ESP"}]}
        bad_ok, bad_msg = self.planner.verify_postconditions(observed_invalid, self.plan)
        self.assertFalse(bad_ok)
        self.assertIn("POSTCONDITION_MISMATCH", bad_msg)


class TestBootHealthSemanticClosure(unittest.TestCase):
    """Verifies Critical #3: Sequential Monotonic Boot State Progression."""

    def test_sequential_monotonic_progression(self):
        contract = BootHealthContract()
        self.assertEqual(contract.status, "INITIALIZING")

        for stage in CONTRACT_STAGES:
            ok = contract.advance_stage(stage)
            self.assertTrue(ok, f"Stage {stage} should advance sequentially")

        self.assertEqual(contract.status, "HEALTH_CONTRACT_SATISFIED")
        healthy, decision = contract.evaluate_contract()
        self.assertTrue(healthy)
        self.assertEqual(decision, "COMMIT_LKG")

    def test_out_of_order_transition_rejection(self):
        contract = BootHealthContract()
        # Jumping directly from INITIALIZING to DESKTOP_TARGET must fail closed
        ok = contract.advance_stage("DESKTOP_TARGET")
        self.assertFalse(ok)
        self.assertEqual(contract.status, "INITIALIZING")
        healthy, decision = contract.evaluate_contract()
        self.assertFalse(healthy)
        self.assertIn("TRIGGER_ROLLBACK", decision)

    def test_probe_stage_condition(self):
        for stage in CONTRACT_STAGES:
            ok, msg = BootHealthContract.probe_stage_condition(stage)
            self.assertTrue(ok)
            self.assertGreater(len(msg), 0)

    def test_recovery_mechanisms_detection(self):
        verifier = MeasuredBootVerifier()
        recovery = verifier.inspect_5_tier_recovery()
        self.assertEqual(len(recovery), 5)
        self.assertIn("tier_1_luks_key_slot_fallback", recovery)
        self.assertIn("tier_2_dual_key_mok", recovery)
        self.assertIn("tier_3_lkg_generation_rollback", recovery)
        self.assertIn("tier_4_sentinel_watchdog", recovery)
        self.assertIn("tier_5_hermetic_fallback_boot", recovery)


class TestSemanticAIGovernance(unittest.TestCase):
    """Verifies Critical #4: Nix AST Grounding, Option Validation, and Dry-Run Diffing."""

    def setUp(self):
        self.engine = SemanticAstEngine(root_dir=PROJECT_ROOT)

    def test_ast_parsing_and_valid_options(self):
        sample_nix = "{ config, pkgs, ... }: { services.openssh.enable = false; }"
        ok, msg, ast = parse_nix_ast(sample_nix)
        self.assertTrue(ok)

    def test_syntax_error_detection(self):
        bad_nix = "{ config, pkgs, ... : unclosed bracket"
        ok, msg, ast = SemanticAstEngine._fallback_lexical_parse(bad_nix)
        self.assertFalse(ok)
        self.assertIn("SYNTAX_ERROR", msg)

    def test_simulate_proposal_success(self):
        proposal = {
            "proposer_mode": True,
            "direct_commit": False,
            "author": "ai_copilot",
            "changes": {
                "services.openssh.enable": False,
                "neuronix.provable_state.enforce": True
            }
        }
        ok, msg, report = self.engine.simulate_proposal(proposal)
        self.assertTrue(ok)
        self.assertEqual(report.get("simulation_verdict"), "ACCEPTED_FOR_OPERATOR_REVIEW")
        self.assertTrue(report.get("safe_for_operator_apply"))

    def test_simulate_proposal_direct_commit_rejection(self):
        # Direct commit violation must fail closed (SEC-019)
        proposal = {
            "proposer_mode": False,
            "direct_commit": True,
            "author": "rogue_ai",
            "changes": {"services.openssh.enable": False}
        }
        ok, msg, _ = self.engine.simulate_proposal(proposal)
        self.assertFalse(ok)
        self.assertIn("FIREWALL_BREACH", msg)

    def test_simulate_proposal_type_mismatch_rejection(self):
        proposal = {
            "proposer_mode": True,
            "direct_commit": False,
            "author": "ai_copilot",
            "changes": {
                "services.openssh.enable": "should_be_a_boolean"
            }
        }
        ok, msg, _ = self.engine.simulate_proposal(proposal)
        self.assertFalse(ok)
        self.assertIn("TYPE_MISMATCH", msg)


class TestLiveSystemTopology(unittest.TestCase):
    """Verifies Critical #5: Live Topology Observation and Effective Convergence."""

    def setUp(self):
        self.engine = SystemTopologyEngine(root_dir=PROJECT_ROOT)

    def test_observe_live_topology(self):
        live = self.engine.observe_live_topology()
        self.assertIn("observed_nodes", live)
        self.assertIn("observed_edges", live)

    def test_build_effective_topology(self):
        effective = self.engine.build_effective_topology()
        self.assertIn("node_count", effective)
        self.assertIn("edge_count", effective)
        self.assertIn("nodes", effective)
        self.assertIn("edges", effective)
        self.assertGreaterEqual(effective.get("node_count", 0), 14)

    def test_blast_radius_calculation(self):
        blast = self.engine.calculate_blast_radius("service:nix_daemon")
        self.assertIn("declared_affected_nodes", blast)
        self.assertIn("observed_affected_nodes", blast)
        self.assertIn("affected_details", blast)
        self.assertGreater(blast.get("affected_count", 0), 0)

    def test_cycle_detection(self):
        cycles = self.engine.detect_cycles()
        self.assertEqual(len(cycles), 0, "Canonical topology must be cycle-free DAG")


class TestStandaloneVerifierClosure(unittest.TestCase):
    """Verifies Critical #6: RFC 8785 Canonical Serializer, DAG Invariants, and Offline Verification."""

    def test_rfc8785_canonical_json_serializer(self):
        d1 = {"z": 1, "a": 2, "m": [3, 2, 1]}
        d2 = {"a": 2, "m": [3, 2, 1], "z": 1}
        self.assertEqual(canonical_json_bytes(d1), canonical_json_bytes(d2))
        self.assertEqual(canonical_json_bytes(d1), b'{"a":2,"m":[3,2,1],"z":1}')

    def test_offline_verification_passport_valid(self):
        passport_path = os.path.join(PROJECT_ROOT, "dist/verification-passport.json")
        self.assertTrue(os.path.exists(passport_path), "Passport file must exist")
        valid, msg, summary = verify_passport(passport_path, check_graph=True)
        self.assertTrue(valid, f"Passport verification failed: {msg}")
        self.assertEqual(summary.get("verified_assertions"), 1264)
        self.assertEqual(summary.get("pass_rate_percentage"), 100)

    def test_offline_release_proof_valid(self):
        proof_path = os.path.join(PROJECT_ROOT, "dist/neuronix-os-v1.0.4.proof.json")
        self.assertTrue(os.path.exists(proof_path), "Release proof file must exist")
        valid, msg, summary = verify_release_proof(proof_path)
        self.assertTrue(valid, f"Release proof verification failed: {msg}")
        self.assertEqual(summary.get("status"), "CERTIFIED_PROVABLE_RELEASE")

    def test_evidence_graph_topological_acyclic_dag(self):
        graph_path = os.path.join(PROJECT_ROOT, "dist/evidence-graph.json")
        self.assertTrue(os.path.exists(graph_path), "Evidence graph file must exist")
        valid, msg, summary = verify_evidence_graph(graph_path)
        self.assertTrue(valid, f"Evidence graph verification failed: {msg}")
        self.assertGreaterEqual(summary.get("node_count", 0), 14)

    def test_backward_lineage_trace(self):
        graph_path = os.path.join(PROJECT_ROOT, "dist/evidence-graph.json")
        trace = trace_graph_lineage(graph_path, start_node="RELEASE_NODE")
        node_ids = [step["node_id"] for step in trace]
        self.assertIn("RELEASE_NODE", node_ids)
        self.assertIn("SOURCE_NODE", node_ids)
        self.assertEqual(node_ids[0], "RELEASE_NODE")
        self.assertEqual(node_ids[-1], "SOURCE_NODE")


if __name__ == "__main__":
    unittest.main()
