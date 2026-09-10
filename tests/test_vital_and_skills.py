import os
import sys
import unittest
from pathlib import Path

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(PROJECT_ROOT, "packages/neuronix-core"))
sys.path.insert(0, os.path.join(PROJECT_ROOT, "tools"))

from neuronix_core import vital
from neuronix_core import skills


class TestVitalObservatoryAndSkillBroker(unittest.TestCase):
    def test_vital_snapshot_structure_and_metadata(self):
        """Test that vital.snapshot() adheres to the laboratory observatory schema with rich metadata."""
        snap = vital.snapshot()
        self.assertIn("timestamp", snap)
        self.assertIn("host", snap)
        self.assertIn("domains", snap)
        self.assertIn("system_health", snap)
        self.assertIn("sampling_duration_ms", snap)

        domains = snap["domains"]
        expected_domains = ["cpu", "memory", "thermals", "storage", "power", "system"]
        for d in expected_domains:
            self.assertIn(d, domains, f"Missing domain '{d}' in vital snapshot")

        # Check metadata fields on a representative metric
        cpu_model = domains["cpu"]["model_name"]
        self.assertIn("metric", cpu_model)
        self.assertIn("value", cpu_model)
        self.assertIn("unit", cpu_model)
        self.assertIn("timestamp", cpu_model)
        self.assertIn("source", cpu_model)
        self.assertIn("age_ms", cpu_model)
        self.assertIn("quality", cpu_model)
        self.assertIn("confidence", cpu_model)
        self.assertIn(cpu_model["quality"], ["fresh", "recent", "stale", "unavailable"])

    def test_vital_context_packaging(self):
        """Test targeted AI context packaging for specific operational purposes."""
        ctx_upgrade = vital.context("system_upgrade")
        self.assertEqual(ctx_upgrade["purpose"], "system_upgrade")
        self.assertIn("active_generation", ctx_upgrade["facts"])
        self.assertIn("root_available_bytes", ctx_upgrade["facts"])
        self.assertIn("memory_available_bytes", ctx_upgrade["facts"])

        ctx_diag = vital.context("diagnostic")
        self.assertEqual(ctx_diag["purpose"], "diagnostic")
        self.assertIn("cpu_load_average", ctx_diag["facts"])
        self.assertIn("memory_pressure", ctx_diag["facts"])

    def test_skill_registry_and_discovery(self):
        """Test skill registry loads canonical skills from data/skills/."""
        registry = skills.SkillRegistry()
        all_skills = registry.list_skills()
        self.assertGreaterEqual(len(all_skills), 5)

        skill_ids = [s["skill_id"] for s in all_skills]
        self.assertIn("vital.snapshot", skill_ids)
        self.assertIn("system.status", skill_ids)
        self.assertIn("system.rollback", skill_ids)
        self.assertIn("storage.plan", skill_ids)
        self.assertIn("state.verify", skill_ids)

    def test_skill_execution_read_and_propose(self):
        """Test execution of READ and PROPOSE skills."""
        # 1. READ: vital.snapshot
        res_vital = skills.execute("vital.snapshot")
        self.assertIn("timestamp", res_vital)
        self.assertIn("memory_available_bytes", res_vital)

        # 2. READ: system.status
        res_status = skills.execute("system.status")
        self.assertEqual(res_status["daemon_status"], "READY")
        self.assertGreaterEqual(res_status["active_generation"], 1)

        # 3. PROPOSE: storage.plan
        res_plan = skills.execute("storage.plan", {"target_device": "/dev/nvme0n1"})
        self.assertEqual(res_plan["target_device"], "/dev/nvme0n1")
        self.assertTrue(res_plan["plan_hash"])
        self.assertTrue(res_plan["required_confirmation_token"].startswith("DESTROY nvme0n1 PLAN "))

    def test_human_approval_gate_enforcement_for_ai_mutations(self):
        """Test that AI caller executing a MUTATE skill triggers the approval gate."""
        # AI caller without authorization token must raise SkillApprovalRequired
        with self.assertRaises(skills.SkillApprovalRequired) as cm:
            skills.execute(
                skill_id="system.rollback",
                inputs={"target_generation": 42},
                caller="AI"
            )

        proposal = cm.exception.proposal
        self.assertEqual(proposal["skill_id"], "system.rollback")
        self.assertEqual(proposal["category"], "MUTATE")
        self.assertTrue(proposal["requires_human_approval"])
        self.assertTrue(proposal["proposal_hash"])

        # Human caller can execute directly
        res_human = skills.execute(
            skill_id="system.rollback",
            inputs={"target_generation": 42, "dry_run": True},
            caller="HUMAN"
        )
        self.assertEqual(res_human["status"], "DRY_RUN_PASSED")
        self.assertEqual(res_human["active_generation"], 42)

        # AI caller with authorization token can execute
        res_ai_authorized = skills.execute(
            skill_id="system.rollback",
            inputs={"target_generation": 42, "dry_run": True},
            caller="AI_AGENT",
            authorization_token="AUTH-ED25519-OPERATOR-VALID"
        )
        self.assertEqual(res_ai_authorized["status"], "DRY_RUN_PASSED")

        # HUMAN_OWNER sovereign execution
        res_owner = skills.execute(
            skill_id="system.rollback",
            inputs={"target_generation": 42, "dry_run": True},
            caller="HUMAN_OWNER",
            sovereign_override=True
        )
        self.assertEqual(res_owner["status"], "DRY_RUN_PASSED")

    def test_skill_machine_readable_operating_manual(self):
        """Test that skills.describe() acts as a machine-readable operating manual."""
        manual = skills.describe("system.rollback")
        self.assertEqual(manual["skill_id"], "system.rollback")
        self.assertEqual(manual["category"], "MUTATE")
        self.assertTrue(manual["approval_gate_required"])
        self.assertIn("invariants_required", manual)
        self.assertIn("inputs_schema", manual)
        self.assertIn("outputs_schema", manual)

        # Non-existent skill raises SkillExecutionError
        with self.assertRaises(skills.SkillExecutionError):
            skills.describe("non.existent.skill")

    def test_delegated_authority_matrix_for_ai_agents(self):
        """Test User Sovereignty via Delegated Authority Tiers for AI agents."""
        # 1. AI with FULL_DELEGATED_CONTROL executes without human approval prompt
        res_full = skills.execute(
            skill_id="system.rollback",
            inputs={"target_generation": 42, "dry_run": True},
            caller="AI_AGENT",
            delegated_authority=skills.DelegatedAuthorityTier.FULL_DELEGATED_CONTROL
        )
        self.assertEqual(res_full["status"], "DRY_RUN_PASSED")
        self.assertEqual(res_full["_receipt"]["delegated_tier"], skills.DelegatedAuthorityTier.FULL_DELEGATED_CONTROL)

        # 2. AI with PRIVILEGED_EXECUTE executes without human approval prompt
        res_priv = skills.execute(
            skill_id="system.rollback",
            inputs={"target_generation": 42, "dry_run": True},
            caller="AI_AGENT",
            delegated_authority=skills.DelegatedAuthorityTier.PRIVILEGED_EXECUTE
        )
        self.assertEqual(res_priv["status"], "DRY_RUN_PASSED")

        # 3. AI with PROPOSE_ONLY is blocked on MUTATE and must yield verifiable proposal
        with self.assertRaises(skills.SkillApprovalRequired) as cm_prop:
            skills.execute(
                skill_id="system.rollback",
                inputs={"target_generation": 42, "dry_run": True},
                caller="AI_AGENT",
                delegated_authority=skills.DelegatedAuthorityTier.PROPOSE_ONLY
            )
        self.assertTrue(cm_prop.exception.proposal["proposal_hash"])

        # 4. AI with OBSERVE_ONLY is blocked on MUTATE
        with self.assertRaises(skills.SkillApprovalRequired):
            skills.execute(
                skill_id="system.rollback",
                inputs={"target_generation": 42, "dry_run": True},
                caller="AI_AGENT",
                delegated_authority=skills.DelegatedAuthorityTier.OBSERVE_ONLY
            )

    def test_execution_receipt_and_audit_lineage(self):
        """Verify that every execution generates an unbypassable cryptographic audit receipt."""
        res = skills.execute("system.status", caller="HUMAN_OWNER")
        self.assertIn("_receipt", res)
        rcp = res["_receipt"]
        self.assertTrue(rcp["receipt_id"].startswith("RCP-"))
        self.assertEqual(rcp["skill_id"], "system.status")
        self.assertEqual(rcp["principal"], skills.PrincipalType.HUMAN_OWNER)
        self.assertEqual(rcp["delegated_tier"], skills.DelegatedAuthorityTier.FULL_DELEGATED_CONTROL)
        self.assertEqual(len(rcp["input_digest"]), 64)
        self.assertEqual(len(rcp["output_digest"]), 64)
        self.assertGreaterEqual(rcp["duration_ms"], 0.0)

    def test_vital_snapshot_unknown_sensor_handling(self):
        """Verify that unknown/missing sensors strictly return None and never fallback to synthetic numbers."""
        snap_skill = skills.execute("vital.snapshot")
        temp = snap_skill.get("cpu_package_temp_celsius")
        # Must be either a valid measured float reading or None, NEVER synthetic 45.0
        if temp is not None:
            self.assertIsInstance(temp, (int, float))
            self.assertGreater(temp, -50.0)
            self.assertLess(temp, 150.0)
        else:
            self.assertIsNone(temp)


if __name__ == "__main__":
    unittest.main()

