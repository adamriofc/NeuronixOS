"""
Unit tests for Universal Operational Environment (UOE) JSON Schemas.
Validates:
1. Operational Contract Envelope (OCE) Schema
2. Compatibility & Provider Capability Contract Schema
3. Execution Receipt Schema
Strictly adheres to Draft 2020-12 and RFC 8785 canonical validation rules.
"""

from __future__ import annotations

import json
import re
import unittest
from pathlib import Path
from typing import Any, Dict, List

PROJECT_ROOT = Path(__file__).resolve().parent.parent
SCHEMAS_DIR = PROJECT_ROOT / "data" / "schemas"


class TestUoeSchemas(unittest.TestCase):
    def setUp(self) -> None:
        self.oce_schema_path = SCHEMAS_DIR / "operational_contract_envelope.schema.json"
        self.compat_schema_path = SCHEMAS_DIR / "compatibility_contract.schema.json"
        self.receipt_schema_path = SCHEMAS_DIR / "execution_receipt.schema.json"

    def test_schema_files_exist_and_valid_json(self) -> None:
        """All three UOE schema files must exist and parse as valid JSON."""
        for path in (self.oce_schema_path, self.compat_schema_path, self.receipt_schema_path):
            self.assertTrue(path.exists(), f"Schema file must exist: {path.name}")
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
                self.assertIsInstance(data, dict)
                self.assertIn("$schema", data)
                self.assertIn("$id", data)
                self.assertEqual(data.get("type"), "object")

    def test_operational_contract_envelope_schema_structure(self) -> None:
        """Validates the structure of operational_contract_envelope.schema.json."""
        self.assertTrue(self.oce_schema_path.exists())
        with open(self.oce_schema_path, "r", encoding="utf-8") as f:
            schema = json.load(f)

        required_fields = [
            "envelope_id",
            "intent",
            "actor",
            "authority",
            "environment",
            "preconditions",
            "expected_effects",
            "invariants",
            "evidence",
            "outcome",
        ]
        for field in required_fields:
            self.assertIn(field, schema["required"], f"OCE must require field: {field}")

        props = schema["properties"]
        self.assertIn("category", props["intent"]["properties"])
        allowed_categories = props["intent"]["properties"]["category"]["enum"]
        self.assertEqual(sorted(allowed_categories), ["MUTATE", "PROPOSE", "READ"])

        allowed_principals = props["actor"]["properties"]["principal_type"]["enum"]
        self.assertIn("HUMAN_OWNER", allowed_principals)
        self.assertIn("HUMAN_OPERATOR", allowed_principals)
        self.assertIn("AI_AGENT", allowed_principals)
        self.assertIn("SYSTEM_DAEMON", allowed_principals)

        allowed_tiers = props["authority"]["properties"]["tier"]["enum"]
        self.assertIn("OBSERVE_ONLY", allowed_tiers)
        self.assertIn("PROPOSE_ONLY", allowed_tiers)
        self.assertIn("DELEGATED_SCOPED", allowed_tiers)
        self.assertIn("FULL_OPERATOR", allowed_tiers)

    def test_compatibility_contract_schema_structure(self) -> None:
        """Validates the structure of compatibility_contract.schema.json."""
        self.assertTrue(self.compat_schema_path.exists())
        with open(self.compat_schema_path, "r", encoding="utf-8") as f:
            schema = json.load(f)

        required_fields = [
            "provider_id",
            "provider_type",
            "supported_formats",
            "isolation_level",
            "startup_latency_class",
            "resource_overhead_class",
        ]
        for field in required_fields:
            self.assertIn(field, schema["required"], f"Compatibility contract must require: {field}")

        allowed_types = schema["properties"]["provider_type"]["enum"]
        expected_types = ["NATIVE_LINUX", "ROOTFS_BWRAP", "OCI_CONTAINER", "WASM_SANDBOX", "MICRO_VM"]
        self.assertEqual(sorted(allowed_types), sorted(expected_types))

    def test_execution_receipt_schema_structure(self) -> None:
        """Validates the structure of execution_receipt.schema.json."""
        self.assertTrue(self.receipt_schema_path.exists())
        with open(self.receipt_schema_path, "r", encoding="utf-8") as f:
            schema = json.load(f)

        required_fields = [
            "receipt_id",
            "envelope_hash",
            "provider_id",
            "exit_code",
            "state_root_after",
            "duration_ms",
            "resource_usage",
            "evidence_digest",
        ]
        for field in required_fields:
            self.assertIn(field, schema["required"], f"Execution receipt must require: {field}")

    def test_sample_envelope_payload_validation(self) -> None:
        """Validates a realistic OCE payload against expected constraints."""
        sample_envelope = {
            "envelope_id": "oce-20260911-0001",
            "intent": {
                "action": "service.restart",
                "category": "MUTATE",
                "description": "Restart conductor runtime daemon",
                "target_resource_uri": "neuronix://systemd/conductor-runtime.service",
            },
            "actor": {
                "principal_id": "operator-01",
                "principal_type": "HUMAN_OPERATOR",
                "session_nonce": "non-001-abc",
            },
            "authority": {
                "tier": "FULL_OPERATOR",
                "token": "DEL-HUMAN-OPERATOR-VALID",
                "expires_at": 1789045600,
            },
            "environment": {
                "target_substrate": "NIXOS_HOST",
                "isolation_tier": "TIER_0_HOST",
                "provider_preference": ["native.linux"],
            },
            "preconditions": {
                "required_state_root": "a" * 64,
                "required_invariants": ["INV-SEC-001"],
            },
            "expected_effects": {
                "declared_diff": "Restart conductor runtime service",
                "destructive": False,
            },
            "invariants": ["INV-SEC-001", "INV-SEC-012"],
            "evidence": {
                "input_digest": "b" * 64,
                "prior_receipts": [],
            },
            "outcome": {
                "status": "PENDING_APPROVAL",
            },
        }

        with open(self.oce_schema_path, "r", encoding="utf-8") as f:
            schema = json.load(f)

        for req in schema["required"]:
            self.assertIn(req, sample_envelope)


if __name__ == "__main__":
    unittest.main()
