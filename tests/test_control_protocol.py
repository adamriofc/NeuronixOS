"""
Unit tests for Conductor Control Protocol Schema v1 (JSON-RPC 2.0 wire format).
Validates request, response, error, and notification frames against SPEC-NRX-CND-018.
"""

import os
import sys
import json
import unittest
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
SCHEMAS_DIR = PROJECT_ROOT / "data" / "schemas"
sys.path.insert(0, str(PROJECT_ROOT / "packages" / "neuronix-core"))

from neuronix_core import skills
from neuronix_core import vital


class TestControlProtocolV1(unittest.TestCase):
    def setUp(self):
        self.schema_path = SCHEMAS_DIR / "control_protocol_v1.json"
        self.assertTrue(self.schema_path.exists(), "control_protocol_v1.json must exist")
        with open(self.schema_path, "r", encoding="utf-8") as f:
            self.schema = json.load(f)

    def test_schema_structure_and_definitions(self):
        """Validates that control_protocol_v1 defines all standard JSON-RPC 2.0 frames."""
        self.assertEqual(self.schema["$schema"], "https://json-schema.org/draft/2020-12/schema")
        self.assertIn("oneOf", self.schema)
        self.assertIn("$defs", self.schema)

        defs = self.schema["$defs"]
        required_defs = ["RequestFrame", "ResponseFrame", "ErrorFrame", "NotificationFrame", "RpcMethod", "RequestId", "ErrorObject"]
        for rd in required_defs:
            self.assertIn(rd, defs, f"Missing definition '{rd}' in schema")

        # Verify all 11 canonical methods are declared
        methods = defs["RpcMethod"]["enum"]
        expected_methods = [
            "conductor.ping",
            "conductor.version",
            "vital.snapshot",
            "vital.subscribe",
            "vital.unsubscribe",
            "skills.list",
            "skills.describe",
            "skills.invoke",
            "identity.resolve",
            "authority.grant",
            "authority.revoke",
            "proposal.resolve",
            "surface.state"
        ]
        for em in expected_methods:
            self.assertIn(em, methods, f"Missing canonical RPC method '{em}'")

    def _validate_frame(self, frame: dict, frame_type: str) -> bool:
        """Lightweight self-contained structural validator against schema frame definition."""
        defs = self.schema["$defs"]
        target_def = defs.get(frame_type)
        self.assertIsNotNone(target_def, f"Frame type '{frame_type}' not in schema")

        # Check required fields
        for req in target_def.get("required", []):
            if req not in frame:
                return False

        # Check jsonrpc version
        if frame.get("jsonrpc") != "2.0":
            return False

        # Check additionalProperties
        if target_def.get("additionalProperties") is False:
            allowed = set(target_def.get("properties", {}).keys())
            if not set(frame.keys()).issubset(allowed):
                return False

        # Specific frame checks
        if frame_type == "RequestFrame":
            if frame.get("method") not in defs["RpcMethod"]["enum"]:
                return False
            if not isinstance(frame.get("id"), (str, int)):
                return False
        elif frame_type == "NotificationFrame":
            if "id" in frame:
                return False
        elif frame_type == "ErrorFrame":
            err = frame.get("error", {})
            if not isinstance(err, dict) or "code" not in err or "message" not in err:
                return False

        return True

    def test_valid_request_frames(self):
        """Test validation of well-formed JSON-RPC 2.0 requests."""
        req1 = {
            "jsonrpc": "2.0",
            "id": "req-001",
            "method": "conductor.ping",
            "params": {"nonce": 12345}
        }
        self.assertTrue(self._validate_frame(req1, "RequestFrame"))

        req2 = {
            "jsonrpc": "2.0",
            "id": 42,
            "method": "skills.invoke",
            "params": {
                "skill_id": "vital.snapshot",
                "caller": "HUMAN_OWNER"
            }
        }
        self.assertTrue(self._validate_frame(req2, "RequestFrame"))

    def test_invalid_request_frames(self):
        """Test rejection of malformed JSON-RPC requests."""
        # Missing jsonrpc
        bad1 = {"id": 1, "method": "conductor.ping"}
        self.assertFalse(self._validate_frame(bad1, "RequestFrame"))

        # Unknown method
        bad2 = {"jsonrpc": "2.0", "id": 1, "method": "unauthorized.exploit"}
        self.assertFalse(self._validate_frame(bad2, "RequestFrame"))

        # Missing id
        bad3 = {"jsonrpc": "2.0", "method": "skills.list"}
        self.assertFalse(self._validate_frame(bad3, "RequestFrame"))

        # Extra disallowed properties
        bad4 = {"jsonrpc": "2.0", "id": 1, "method": "conductor.ping", "illegal_field": True}
        self.assertFalse(self._validate_frame(bad4, "RequestFrame"))

    def test_response_and_error_frames(self):
        """Test validation of success responses and error envelopes."""
        resp = {
            "jsonrpc": "2.0",
            "id": "req-001",
            "result": {
                "version": "1.0.5",
                "status": "READY"
            }
        }
        self.assertTrue(self._validate_frame(resp, "ResponseFrame"))

        err = {
            "jsonrpc": "2.0",
            "id": "req-002",
            "error": {
                "code": -32002,
                "message": "Human approval gate required",
                "data": {"proposal_hash": "abc123"}
            }
        }
        self.assertTrue(self._validate_frame(err, "ErrorFrame"))

    def test_notification_frame(self):
        """Test validation of notifications without request IDs."""
        notif = {
            "jsonrpc": "2.0",
            "method": "vital.snapshot",
            "params": {"frequency_ms": 1000}
        }
        self.assertTrue(self._validate_frame(notif, "NotificationFrame"))

        # Notification with ID must be rejected
        bad_notif = {
            "jsonrpc": "2.0",
            "id": "should_not_have_id",
            "method": "vital.snapshot"
        }
        self.assertFalse(self._validate_frame(bad_notif, "NotificationFrame"))

    def test_wire_dispatch_simulation(self):
        """Simulate an end-to-end wire call through the control protocol into the core engine."""
        request_payload = {
            "jsonrpc": "2.0",
            "id": "call-101",
            "method": "skills.invoke",
            "params": {
                "skill_id": "vital.snapshot",
                "caller": "HUMAN_OWNER"
            }
        }
        self.assertTrue(self._validate_frame(request_payload, "RequestFrame"))

        # Dispatch
        skill_res = skills.execute(
            skill_id=request_payload["params"]["skill_id"],
            caller=request_payload["params"]["caller"]
        )

        response_payload = {
            "jsonrpc": "2.0",
            "id": request_payload["id"],
            "result": skill_res
        }
        self.assertTrue(self._validate_frame(response_payload, "ResponseFrame"))
        self.assertIn("memory_available_bytes", response_payload["result"])
        self.assertIn("_receipt", response_payload["result"])


if __name__ == "__main__":
    unittest.main()
