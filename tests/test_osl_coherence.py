"""
Unit tests for CoherenceEngine and Operational Semantic Layer (OSL).
Validates selective semanticization tiers (Tier 0 to Tier 2), invariant enforcement,
StateRoot preflight validation, and AI agent approval gates.
"""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT / "packages" / "neuronix-core"))

from neuronix_core import skills
from neuronix_core.osl.coherence import (
    CoherenceApprovalRequired,
    CoherenceEngine,
    CoherenceInvariantViolation,
    CoherenceStateRootMismatch,
    CoherenceUnexecutableError,
    CoherenceVerdict,
)
from neuronix_core.uef.resolver import create_default_resolver


class TestOslCoherence(unittest.TestCase):
    def setUp(self) -> None:
        self.resolver = create_default_resolver()
        self.engine = CoherenceEngine(resolver=self.resolver)

    def test_tier_0_passthrough_read_operation(self) -> None:
        """READ operations qualify for Tier 0 passthrough with near-zero overhead."""
        envelope = {
            "envelope_id": "oce-read-001",
            "intent": {
                "action": "system.status",
                "category": "READ",
                "description": "Probe system status",
                "target_resource_uri": "neuronix://system/status",
            },
            "actor": {
                "principal_id": "agent-01",
                "principal_type": "AI_AGENT",
                "session_nonce": "nonce-read-01",
            },
            "authority": {"tier": "OBSERVE_ONLY"},
            "environment": {
                "target_substrate": "NIXOS_HOST",
                "isolation_tier": "TIER_0_HOST",
            },
            "preconditions": {"required_state_root": "0" * 64},
            "expected_effects": {"declared_diff": "", "destructive": False},
            "invariants": ["INV-SEC-001"],
            "evidence": {"input_digest": "0" * 64},
            "outcome": {"status": "PENDING_EVALUATION"},
        }

        verdict = self.engine.evaluate_envelope(envelope, current_state_root="0" * 64)
        self.assertTrue(verdict.authorized)
        self.assertEqual(verdict.semantic_tier, "TIER_0_PASSTHROUGH")

    def test_tier_2_mutate_requires_human_approval_for_ai_agent(self) -> None:
        """MUTATE operations initiated by AI_AGENT without valid delegation require approval."""
        envelope = {
            "envelope_id": "oce-mutate-001",
            "intent": {
                "action": "storage.repartition",
                "category": "MUTATE",
                "description": "Repartition NVMe drive",
                "target_resource_uri": "neuronix://storage/nvme0n1",
            },
            "actor": {
                "principal_id": "agent-01",
                "principal_type": "AI_AGENT",
                "session_nonce": "nonce-mut-01",
            },
            "authority": {"tier": "PROPOSE_ONLY"},
            "environment": {
                "target_substrate": "NIXOS_HOST",
                "isolation_tier": "TIER_1_SANDBOX",
            },
            "preconditions": {"required_state_root": "f" * 64},
            "expected_effects": {"declared_diff": "Format partition", "destructive": True},
            "invariants": ["INV-SEC-012"],
            "evidence": {"input_digest": "e" * 64},
            "outcome": {"status": "PENDING_EVALUATION"},
        }

        with self.assertRaises(CoherenceApprovalRequired) as cm:
            self.engine.evaluate_envelope(envelope, current_state_root="f" * 64)

        self.assertIn("Human approval required", str(cm.exception))

    def test_tier_2_mutate_authorized_with_valid_operator(self) -> None:
        """MUTATE operations authorized when operator has FULL_OPERATOR tier."""
        envelope = {
            "envelope_id": "oce-mutate-002",
            "intent": {
                "action": "service.restart",
                "category": "MUTATE",
                "description": "Restart conductor daemon",
                "target_resource_uri": "neuronix://systemd/conductor.service",
            },
            "actor": {
                "principal_id": "operator-01",
                "principal_type": "HUMAN_OPERATOR",
                "session_nonce": "nonce-mut-02",
            },
            "authority": {
                "tier": "FULL_OPERATOR",
                "token": "DEL-HUMAN-OPERATOR-VALID",
            },
            "environment": {
                "target_substrate": "NIXOS_HOST",
                "isolation_tier": "TIER_0_HOST",
            },
            "preconditions": {"required_state_root": "a" * 64},
            "expected_effects": {"declared_diff": "Restart service", "destructive": False},
            "invariants": ["INV-SEC-001"],
            "evidence": {"input_digest": "b" * 64},
            "outcome": {"status": "PENDING_EVALUATION"},
        }

        verdict = self.engine.evaluate_envelope(envelope, current_state_root="a" * 64)
        self.assertTrue(verdict.authorized)
        self.assertEqual(verdict.semantic_tier, "TIER_2_FULL_CONTRACT")

    def test_stateroot_mismatch_fails_closed(self) -> None:
        """Precondition StateRoot mismatch immediately rejects envelope."""
        envelope = {
            "envelope_id": "oce-mismatch-001",
            "intent": {
                "action": "system.upgrade",
                "category": "MUTATE",
                "description": "System upgrade",
                "target_resource_uri": "neuronix://system/upgrade",
            },
            "actor": {
                "principal_id": "operator-01",
                "principal_type": "HUMAN_OPERATOR",
                "session_nonce": "nonce-03",
            },
            "authority": {"tier": "FULL_OPERATOR", "token": "DEL-VALID"},
            "environment": {"target_substrate": "NIXOS_HOST", "isolation_tier": "TIER_0_HOST"},
            "preconditions": {"required_state_root": "1" * 64},
            "expected_effects": {"declared_diff": "Upgrade NixOS generation", "destructive": False},
            "invariants": ["INV-SEC-001"],
            "evidence": {"input_digest": "2" * 64},
            "outcome": {"status": "PENDING_EVALUATION"},
        }

        with self.assertRaises(CoherenceStateRootMismatch):
            self.engine.evaluate_envelope(envelope, current_state_root="9" * 64)

    def test_ai_agent_mutation_authorized_with_authentic_delegation(self) -> None:
        """AI agent with authentic, registered delegation is authorized for Tier 2 mutation."""
        dispatcher = skills.get_dispatcher()
        grant = dispatcher.delegations.grant(
            principal_id="agent-trusted",
            tier=skills.DelegatedAuthorityTier.PRIVILEGED_EXECUTE,
            scope=["storage.repartition"],
            input_digest="d" * 64,
        )

        envelope = {
            "envelope_id": "oce-auth-001",
            "intent": {
                "action": "storage.repartition",
                "category": "MUTATE",
                "description": "Partition drive under verified delegation",
            },
            "actor": {
                "principal_id": "agent-trusted",
                "principal_type": "AI_AGENT",
            },
            "authority": {
                "tier": "DELEGATED_SCOPED",
                "token": grant.token,
            },
            "environment": {"isolation_tier": "TIER_1_SANDBOX"},
            "preconditions": {},
            "evidence": {"input_digest": "d" * 64},
        }

        verdict = self.engine.evaluate_envelope(envelope)
        self.assertTrue(verdict.authorized)
        self.assertEqual(verdict.semantic_tier, "TIER_2_FULL_CONTRACT")

    def test_ai_agent_mutation_rejected_with_magic_prefix_token(self) -> None:
        """Heuristic/magic token prefix without authoritative registry record is firmly rejected."""
        envelope = {
            "envelope_id": "oce-unauth-001",
            "intent": {
                "action": "storage.repartition",
                "category": "MUTATE",
            },
            "actor": {
                "principal_id": "agent-untrusted",
                "principal_type": "AI_AGENT",
            },
            "authority": {
                "tier": "DELEGATED_SCOPED",
                "token": "DEL-MAGIC-STRING-NOT-IN-REGISTRY",
            },
            "evidence": {"input_digest": "0" * 64},
        }

        with self.assertRaises(CoherenceApprovalRequired):
            self.engine.evaluate_envelope(envelope)

    def test_ai_agent_mutation_rejected_with_wrong_scope(self) -> None:
        """Delegation valid for skill A cannot be used to authorize skill B."""
        dispatcher = skills.get_dispatcher()
        grant = dispatcher.delegations.grant(
            principal_id="agent-scoped",
            tier=skills.DelegatedAuthorityTier.PRIVILEGED_EXECUTE,
            scope=["system.status"],  # Not authorized for storage.repartition
        )

        envelope = {
            "envelope_id": "oce-wrong-scope-001",
            "intent": {
                "action": "storage.repartition",
                "category": "MUTATE",
            },
            "actor": {
                "principal_id": "agent-scoped",
                "principal_type": "AI_AGENT",
            },
            "authority": {
                "tier": "DELEGATED_SCOPED",
                "token": grant.token,
            },
        }

        with self.assertRaises(CoherenceApprovalRequired):
            self.engine.evaluate_envelope(envelope)

    def test_invariant_violation_fails_closed(self) -> None:
        """Malformed invariant syntax or secret leakage triggers CoherenceInvariantViolation."""
        # Malformed invariant
        envelope_bad_inv = {
            "intent": {"action": "system.probe", "category": "READ"},
            "invariants": ["NOT-A-VALID-INVARIANT"],
        }
        with self.assertRaises(CoherenceInvariantViolation):
            self.engine.evaluate_envelope(envelope_bad_inv)

        # Secret leakage invariant INV-SEC-014 violation
        envelope_secret_leak = {
            "intent": {"action": "system.probe", "category": "READ"},
            "invariants": ["INV-SEC-014"],
            "environment": {"leaked_key": "AGE-SECRET-KEY-10000000000000000000000000000000000000000000000000000000000"},
        }
        with self.assertRaises(CoherenceInvariantViolation):
            self.engine.evaluate_envelope(envelope_secret_leak)

    def test_execute_envelope_unexecutable_fails_closed(self) -> None:
        """Unexecutable action without entrypoint or skill mapping strictly raises CoherenceUnexecutableError."""
        envelope = {
            "envelope_id": "oce-unexec-001",
            "intent": {
                "action": "nonexistent.completely_fake_skill",
                "category": "READ",
            },
            "actor": {"principal_type": "HUMAN_OPERATOR"},
            "authority": {"tier": "FULL_OPERATOR"},
        }

        with self.assertRaises(CoherenceUnexecutableError):
            self.engine.execute_envelope(envelope)

    def test_execute_envelope_truthful_execution_receipt(self) -> None:
        """Verifies truthful execution receipt with RFC 8785 envelope hash and live state root."""
        envelope = {
            "envelope_id": "oce-exec-001",
            "intent": {
                "action": "system.test_echo",
                "category": "READ",
                "entrypoint": ["/bin/echo"],
                "arguments": ["COHERENCE_AUTHENTIC_EXEC"],
            },
            "actor": {
                "principal_id": "operator-01",
                "principal_type": "HUMAN_OPERATOR",
            },
            "authority": {"tier": "FULL_OPERATOR"},
            "invariants": ["INV-SEC-001"],
        }

        receipt = self.engine.execute_envelope(envelope)
        self.assertEqual(receipt.exit_code, 0)
        self.assertIn("COHERENCE_AUTHENTIC_EXEC", receipt.stdout_preview)
        self.assertEqual(len(receipt.envelope_hash), 64)
        self.assertEqual(len(receipt.state_root_after), 64)
        self.assertIn("INV-SEC-001", receipt.invariants_verified)


if __name__ == "__main__":
    unittest.main()
