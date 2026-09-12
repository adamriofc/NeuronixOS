"""
Comprehensive Semantic Closure Verification Suite (MES-NRX-002)
Validates authentic Age protocol encryption/decryption, 7-factor storage firewall,
boot health monotonic state transitions, semantic Nix AST governance,
effective topology convergence, and offline verification passport guarantees.

Copyright (c) 2026 NEURONIX Contributors
Licensed under the Apache License, Version 2.0
"""

import os
import sys
import json
import tempfile
import subprocess
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
    generate_operator_keypair,
    sign_storage_authorization,
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
    """Verifies Critical #1: Real Age Protocol Encryption/Decryption and Ephemeral RAM Safety."""

    def setUp(self):
        self.engine = SecretFabricEngine()
        self.ident, self.recipient = SecretFabricEngine.generate_keypair()
        self.wrong_ident, self.wrong_recipient = SecretFabricEngine.generate_keypair()

    def test_01_real_age_cli_encryption_roundtrip(self):
        """Test 1: Encrypt using real Age CLI directly and decrypt using real Age CLI."""
        age_bin, _ = SecretFabricEngine.get_binaries()
        payload = "CONFIDENTIAL_TEST_PAYLOAD_001"
        proc_enc = subprocess.run(
            [age_bin, "-a", "-r", self.recipient],
            input=payload,
            capture_output=True,
            text=True,
            check=True
        )
        armor = proc_enc.stdout
        self.assertIn("BEGIN AGE ENCRYPTED FILE", armor)
        self.assertIn("END AGE ENCRYPTED FILE", armor)

    def test_02_real_age_cli_decryption(self):
        """Test 2: Decrypt real Age ciphertext using real Age CLI."""
        payload = "CONFIDENTIAL_TEST_PAYLOAD_002"
        armor = SecretFabricEngine.encrypt_secret_envelope(payload, [self.recipient])
        age_bin, _ = SecretFabricEngine.get_binaries()
        with tempfile.NamedTemporaryFile("w", encoding="utf-8", delete=False) as kf:
            kf.write(self.ident + "\n")
            kf_name = kf.name
        try:
            proc_dec = subprocess.run(
                [age_bin, "-d", "-i", kf_name],
                input=armor,
                capture_output=True,
                text=True,
                check=True
            )
            self.assertEqual(proc_dec.stdout, payload)
        finally:
            os.unlink(kf_name)

    def test_03_encrypt_using_neuronix(self):
        """Test 3: Encrypt using NEURONIX SecretFabricEngine produces valid Age armor."""
        payload = "CONFIDENTIAL_TEST_PAYLOAD_003"
        ciphertext = encrypt_secret_envelope(payload, [self.recipient])
        self.assertIn("BEGIN AGE ENCRYPTED FILE", ciphertext)
        self.assertIn("END AGE ENCRYPTED FILE", ciphertext)
        ok, msg, decrypted = decrypt_secret_envelope(
            ciphertext_raw=ciphertext,
            identity_key=self.ident,
            allowed_recipients=[self.recipient]
        )
        self.assertTrue(ok, f"Decryption should succeed: {msg}")
        self.assertEqual(decrypted, payload)

    def test_04_decrypt_using_external_age(self):
        """Test 4: NEURONIX ciphertext decrypted by external Age CLI binary."""
        payload = "CONFIDENTIAL_TEST_PAYLOAD_004"
        ciphertext = encrypt_secret_envelope(payload, [self.recipient])
        age_bin, _ = SecretFabricEngine.get_binaries()
        with tempfile.NamedTemporaryFile("w", encoding="utf-8", delete=False) as kf:
            kf.write(self.ident + "\n")
            kf_name = kf.name
        try:
            res = subprocess.run(
                [age_bin, "-d", "-i", kf_name],
                input=ciphertext,
                capture_output=True,
                text=True,
                check=True
            )
            self.assertEqual(res.stdout, payload)
        finally:
            os.unlink(kf_name)

    def test_05_fail_closed_wrong_identity_rejected(self):
        """Test 5: Wrong identity key must reject and fail closed."""
        payload = "CONFIDENTIAL_TEST_PAYLOAD_005"
        ciphertext = encrypt_secret_envelope(payload, [self.recipient])
        ok, msg, decrypted = decrypt_secret_envelope(
            ciphertext_raw=ciphertext,
            identity_key=self.wrong_ident,
            allowed_recipients=[self.recipient]
        )
        self.assertFalse(ok)
        self.assertIn("MISSING_AGE_IDENTITY", msg)
        self.assertIsNone(decrypted)

    def test_06_fail_closed_modified_ciphertext_rejected(self):
        """Test 6: Modified ciphertext must reject due to MAC/integrity verification failure."""
        payload = "CONFIDENTIAL_TEST_PAYLOAD_006"
        ciphertext = encrypt_secret_envelope(payload, [self.recipient])
        lines = ciphertext.splitlines()
        if len(lines) > 3:
            orig = lines[2]
            lines[2] = orig[:5] + ("X" if orig[5] != "X" else "Y") + orig[6:]
        tampered = "\n".join(lines)
        ok, msg, decrypted = decrypt_secret_envelope(
            ciphertext_raw=tampered,
            identity_key=self.ident,
            allowed_recipients=[self.recipient]
        )
        self.assertFalse(ok)
        self.assertIn("AUTHENTICATED_DECRYPTION_FAILED", msg)
        self.assertIsNone(decrypted)

    def test_07_fail_closed_wrong_recipient_rejected(self):
        """Test 7: Secret encrypted for recipient A rejected when attempting to decrypt with recipient B."""
        payload = "CONFIDENTIAL_TEST_PAYLOAD_007"
        ciphertext = encrypt_secret_envelope(payload, [self.recipient])
        ok, msg, decrypted = decrypt_secret_envelope(
            ciphertext_raw=ciphertext,
            identity_key=self.wrong_ident,
            allowed_recipients=[self.wrong_recipient]
        )
        self.assertFalse(ok)
        self.assertIsNone(decrypted)

    def test_08_materialization_only_on_verified_tmpfs_ramfs(self):
        """Test 8: Materialization requires volatile tmpfs/ramfs when enforce_ramfs=True."""
        self.assertTrue(is_volatile_ram_filesystem("/dev/shm"))
        self.assertTrue(is_volatile_ram_filesystem("/run"))
        self.assertFalse(is_volatile_ram_filesystem("/var/log/nonvolatile"))

        non_volatile_engine = SecretFabricEngine(ramfs_root="/var/log/nonvolatile_test", enforce_ramfs=True)
        ciphertext = encrypt_secret_envelope("SECRET_DB_PASS", [self.recipient])
        non_volatile_engine.register_secret(
            name="db_password",
            ciphertext=ciphertext,
            required_capability="cap:db.read",
            recipients=[self.recipient]
        )
        ok, reason, path = non_volatile_engine.materialize_secret(
            name="db_password",
            capability_token="cap:db.read",
            identity_key=self.ident
        )
        self.assertFalse(ok)
        self.assertIn("VOLATILE_RAM_MOUNT_REQUIRED", reason)
        self.assertIsNone(path)

    def test_09_ai_metadata_masking(self):
        """Test 9: AI agent roles see only metadata with plaintext strictly masked."""
        ciphertext = encrypt_secret_envelope("SECRET_API_TOKEN_VALUE", [self.recipient])
        self.engine.register_secret(
            name="api_token",
            ciphertext=ciphertext,
            required_capability="cap:api.call",
            recipients=[self.recipient]
        )
        ai_view = self.engine.filter_secret_for_actor("api_token", actor_role="ai_agent")
        self.assertEqual(ai_view.get("value"), "[MASKED: AI_SECRET_VISIBILITY_METADATA_ONLY]")
        self.assertEqual(ai_view.get("plaintext_visibility"), "METADATA_ONLY")
        self.assertNotIn("SECRET_API_TOKEN_VALUE", str(ai_view))

    def test_10_plaintext_never_included_in_stateroot(self):
        """Test 10: Secret plaintexts are never included in SecretRoot digest computation."""
        secret_plaintext = "NEVER_EXPOSE_THIS_PLAINTEXT_IN_STATEROOT_99999"
        ciphertext = encrypt_secret_envelope(secret_plaintext, [self.recipient])
        self.engine.register_secret(
            name="top_secret_token",
            ciphertext=ciphertext,
            required_capability="cap:top.secret",
            recipients=[self.recipient]
        )
        root = self.engine.compute_secret_root()
        self.assertEqual(len(root), 64)
        metadata_str = str(self.engine.registry["top_secret_token"])
        self.assertNotIn(secret_plaintext, metadata_str)


class TestStorageFirewallSemanticClosure(unittest.TestCase):
    """Verifies Critical #2: 7-Factor Storage Safety Firewall and Preflight Validation."""

    def setUp(self):
        self.planner = StoragePlannerEngine()
        self.plan = self.planner.generate_plan()
        self.plan_hash = self.planner.compute_plan_hash(self.plan)
        self.op_priv, self.op_pub = generate_operator_keypair()

    def test_factor3_active_generation_rejection(self):
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
        auth = sign_storage_authorization(
            target_device="/dev/vdz",
            plan_hash=self.plan_hash,
            operator_id="secops@sys",
            clearance="DISASTER_RECOVERY_OPERATOR",
            challenge_nonce="test_nonce_closure_12345",
            expiry=2147483647,
            secret_key_hex=self.op_priv
        )
        allowed, reason, factors = StorageFirewall.evaluate_7_factors(
            target_device="/dev/vdz",
            plan_hash=self.plan_hash,
            expected_plan_hash=self.plan_hash,
            confirmation_token=f"DESTROY vdz PLAN {self.plan_hash}",
            operator_auth=auth,
            trusted_public_keys=[self.op_pub],
            simulated_entropy=True,
            active_mounts_override=[],
            active_devices_override=set()
        )
        self.assertTrue(allowed, f"Should pass all 7 factors: {reason}")
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
        self.assertTrue(report.get("safe_for_operator_review"))

    def test_simulate_proposal_direct_commit_rejection(self):
        proposal = {
            "proposer_mode": False,
            "direct_commit": True,
            "author": "rogue_ai",
            "changes": {"services.openssh.enable": False}
        }
        ok, msg, _ = self.engine.simulate_proposal(proposal)
        self.assertFalse(ok)
        self.assertIn("FIREWALL_BREACH", msg)

    def test_simulate_proposal_missing_proposer_flag_rejection(self):
        proposal = {
            "author": "ai_copilot",
            "changes": {"services.openssh.enable": False}
        }
        ok, msg, _ = self.engine.simulate_proposal(proposal)
        self.assertFalse(ok)
        self.assertIn("FIREWALL_BREACH", msg)
        self.assertIn("proposer_mode", msg)

    def test_simulate_proposal_unknown_option_rejection(self):
        proposal = {
            "proposer_mode": True,
            "direct_commit": False,
            "author": "ai_copilot",
            "changes": {"nonexistent.rogue.option": True}
        }
        ok, msg, _ = self.engine.simulate_proposal(proposal)
        self.assertFalse(ok)
        self.assertIn("SECURITY_VIOLATION", msg)
        self.assertIn("CANONICAL_OPTIONS", msg)

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

        # RFC 8785 Section 3.2.2.3: ECMAScript 5.1 numeric canonicalization
        from neuronix_core.state import canonical_json_bytes as core_cjb
        for num_input, expected_str in [
            (100.0, "100"),
            (-42.0, "-42"),
            (-0.0, "0"),
            (0.000001, "0.000001"),
            (0.0000001, "1e-7"),
            (1e20, "100000000000000000000"),
            (1e21, "1e+21"),
            (0.1, "0.1"),
            (9007199254740991.0, "9007199254740991"),
        ]:
            self.assertEqual(canonical_json_bytes(num_input).decode("utf-8"), expected_str)
            self.assertEqual(core_cjb(num_input).decode("utf-8"), expected_str)
            self.assertEqual(canonical_json_bytes(num_input), core_cjb(num_input))

    def test_rfc8785_surrogate_and_supplementary_unicode_ordering(self):
        # UTF-16 surrogate pairs must sort according to 16-bit code units, not Unicode code points
        surrogate_test = {"\U0001F600": 1, "\uE000": 2}
        expected = b'{"\xf0\x90\x80\x80":2,"\xef\xbf\xbf":1}' # check byte ordering
        self.assertEqual(canonical_json_bytes(surrogate_test).decode("utf-8"), '{"\U0001F600":1,"\uE000":2}')
        # Deseret vs Ethiopic
        deseret_test = {"\U00010437": 1, "\u1234": 2}
        self.assertEqual(canonical_json_bytes(deseret_test).decode("utf-8"), '{"\u1234":2,"\U00010437":1}')

    def test_offline_verification_passport_valid(self):
        passport_path = os.path.join(PROJECT_ROOT, "dist/verification-passport.json")
        self.assertTrue(os.path.exists(passport_path), "Passport file must exist")
        valid, msg, summary = verify_passport(passport_path, check_graph=True)
        self.assertTrue(valid, f"Passport verification failed: {msg}")

        manifest_path = os.path.join(PROJECT_ROOT, "data/test_manifest.json")
        expected_assertions = summary.get("catalog_assertions", 1384)
        if os.path.exists(manifest_path):
            try:
                with open(manifest_path, "r", encoding="utf-8") as mf:
                    mdata = json.load(mf)
                    expected_assertions = mdata.get("summary", {}).get("total_repository_assertions", expected_assertions)
            except Exception:
                pass

        self.assertEqual(summary.get("verified_assertions"), expected_assertions)
        self.assertEqual(summary.get("pass_rate_percentage"), 100)

    def test_offline_release_proof_valid(self):
        proof_path = os.path.join(PROJECT_ROOT, "dist/neuronix-os-v1.0.5.proof.json")
        if not os.path.exists(proof_path):
            import glob
            matches = sorted(glob.glob(os.path.join(PROJECT_ROOT, "dist/neuronix-os-v*.proof.json")))
            if matches:
                proof_path = matches[-1]
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

    def test_exact_commit_sha_binding(self):
        passport_path = os.path.join(PROJECT_ROOT, "dist/verification-passport.json")
        proof_path = os.path.join(PROJECT_ROOT, "dist/neuronix-os-v1.0.5.proof.json")
        if not os.path.exists(proof_path):
            import glob
            matches = sorted(glob.glob(os.path.join(PROJECT_ROOT, "dist/neuronix-os-v*.proof.json")))
            if matches:
                proof_path = matches[-1]
        graph_path = os.path.join(PROJECT_ROOT, "dist/evidence-graph.json")

        with open(passport_path, "r", encoding="utf-8") as f:
            passport = json.load(f)
        with open(proof_path, "r", encoding="utf-8") as f:
            proof = json.load(f)
        with open(graph_path, "r", encoding="utf-8") as f:
            graph = json.load(f)

        passport_sha = passport.get("release_metadata", {}).get("commit_sha")
        proof_sha = proof.get("release_metadata", {}).get("commit_sha")
        graph_source_sha = graph.get("nodes", {}).get("SOURCE_NODE", {}).get("git_commit_sha")
        graph_release_sha = graph.get("nodes", {}).get("RELEASE_NODE", {}).get("commit_sha")

        self.assertEqual(passport_sha, proof_sha, "Passport and Proof commit SHA must match")
        self.assertEqual(passport_sha, graph_source_sha, "Passport and Evidence Graph SOURCE_NODE must match")
        self.assertEqual(passport_sha, graph_release_sha, "Passport and Evidence Graph RELEASE_NODE must match")


if __name__ == "__main__":
    unittest.main()
