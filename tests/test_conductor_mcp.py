"""
Unit tests for Conductor MCP 2026-07-28 Universal Agent Adapter.
Validates protocol initialization, tool catalog translation, delegated execution,
approval gate error handling, and laboratory resource endpoints.
Adheres strictly to SPEC-NRX-CND-018, SPEC-NRX-SKL-019, and SPEC-NRX-CND-021.
"""

import sys
import json
import unittest
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT / "packages" / "neuronix-core"))
sys.path.insert(0, str(PROJECT_ROOT / "packages" / "conductor-runtime"))
sys.path.insert(0, str(PROJECT_ROOT / "packages" / "conductor-mcp"))

from conductor_mcp.server import McpServer
from neuronix_core import skills


class TestConductorMcpServer(unittest.TestCase):
    def setUp(self):
        self.server = McpServer()

    def test_mcp_initialization(self):
        """Test protocol discovery for modern MCP 2026-07-28 and legacy backwards compatibility."""
        # 1. Modern MCP 2026-07-28 uses server/discover discovery mechanism
        req_discover = {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "server/discover"
        }
        res_discover = self.server.handle_request(req_discover)
        self.assertEqual(res_discover["jsonrpc"], "2.0")
        self.assertEqual(res_discover["id"], 1)
        self.assertIn("tools", res_discover["result"]["capabilities"])
        self.assertIn("resources", res_discover["result"]["capabilities"])
        self.assertIn("2026-07-28", res_discover["result"]["supportedProtocolVersions"])

        # 2. Modern MCP 2026-07-28 is strictly stateless and rejects initialize
        req_modern_init = {
            "jsonrpc": "2.0",
            "id": 2,
            "method": "initialize",
            "params": {
                "protocolVersion": "2026-07-28",
                "clientInfo": {"name": "test-client", "version": "1.0.0"}
            }
        }
        res_modern_init = self.server.handle_request(req_modern_init)
        self.assertIn("error", res_modern_init)
        self.assertIn("stateless", res_modern_init["error"]["message"])

        # 3. Test legacy 2024-11-05 backwards compatibility
        req_legacy = {
            "jsonrpc": "2.0",
            "id": 3,
            "method": "initialize",
            "params": {"protocolVersion": "2024-11-05"}
        }
        res_legacy = self.server.handle_request(req_legacy)
        self.assertEqual(res_legacy["result"]["protocolVersion"], "2024-11-05")

        # 4. Wrong protocol metadata in _meta is strictly rejected
        req_wrong_meta = {
            "jsonrpc": "2.0",
            "id": 4,
            "method": "tools/call",
            "params": {
                "name": "vital.snapshot",
                "arguments": {},
                "_meta": {"protocolVersion": "1999-01-01"}
            }
        }
        res_wrong_meta = self.server.handle_request(req_wrong_meta)
        self.assertIn("error", res_wrong_meta)
        self.assertIn("unsupported protocolversion", res_wrong_meta["error"]["message"].lower())

    def test_tools_list_translation(self):
        """Test dynamic translation of NEURONIX Skill Registry to MCP tool list."""
        req = {
            "jsonrpc": "2.0",
            "id": 3,
            "method": "tools/list"
        }
        res = self.server.handle_request(req)
        tools = res["result"]["tools"]
        self.assertGreaterEqual(len(tools), 5)

        tool_names = [t["name"] for t in tools]
        self.assertIn("vital.snapshot", tool_names)
        self.assertIn("system.status", tool_names)
        self.assertIn("system.rollback", tool_names)
        self.assertIn("storage.plan", tool_names)
        self.assertIn("state.verify", tool_names)

        # Check structure
        for t in tools:
            self.assertIn("name", t)
            self.assertIn("description", t)
            self.assertIn("inputSchema", t)

    def test_tool_call_read(self):
        """Test executing a READ skill via MCP tools/call."""
        req = {
            "jsonrpc": "2.0",
            "id": 4,
            "method": "tools/call",
            "params": {
                "name": "vital.snapshot",
                "arguments": {}
            }
        }
        res = self.server.handle_request(req)
        self.assertFalse(res["result"]["isError"])
        content = res["result"]["content"][0]
        self.assertEqual(content["type"], "text")
        parsed = json.loads(content["text"])
        self.assertIn("timestamp", parsed)
        self.assertIn("memory_available_bytes", parsed)

    def test_tool_call_mutate_approval_gate(self):
        """Test that autonomous AI agent invoking MUTATE skill without delegation triggers approval error."""
        req = {
            "jsonrpc": "2.0",
            "id": 5,
            "method": "tools/call",
            "params": {
                "name": "system.rollback",
                "arguments": {"target_generation": 42, "dry_run": True},
                "_meta": {
                    "caller_id": "external-claude-agent",
                    "delegated_authority": skills.DelegatedAuthorityTier.PROPOSE_ONLY
                }
            }
        }
        res = self.server.handle_request(req)
        self.assertTrue(res["result"]["isError"])
        text = res["result"]["content"][0]["text"]
        self.assertIn("APPROVAL_REQUIRED", text)
        self.assertIn("Proposal Hash:", text)

    def test_tool_call_mutate_with_delegated_authority(self):
        """Test User Sovereignty: AI agent with authentic delegated mutation token executes cleanly."""
        # Issue an authentic sovereign delegation token
        grant = skills.grant_delegation(
            principal_id="external-claude-agent",
            tier=skills.DelegatedAuthorityTier.FULL_DELEGATED_CONTROL,
            scope=["system.rollback"]
        )
        token = grant["token"]

        req = {
            "jsonrpc": "2.0",
            "id": 6,
            "method": "tools/call",
            "params": {
                "name": "system.rollback",
                "arguments": {"target_generation": 42, "dry_run": True},
                "_meta": {
                    "authorization_token": token
                }
            }
        }
        res = self.server.handle_request(req)
        self.assertFalse(res["result"]["isError"])
        text = res["result"]["content"][0]["text"]
        parsed = json.loads(text)
        self.assertEqual(parsed["status"], "DRY_RUN_PASSED")
        self.assertIn("_receipt", parsed)

        # Ensure revoked token fails closed
        skills.revoke_delegation(grant["delegation_id"])
        res_revoked = self.server.handle_request(req)
        self.assertTrue(res_revoked["result"]["isError"])
        self.assertTrue(
            "revoked" in res_revoked["result"]["content"][0]["text"].lower() or
            "APPROVAL_REQUIRED" in res_revoked["result"]["content"][0]["text"]
        )

    def test_resources_list_and_read(self):
        """Test accessing Vital laboratory telemetry as MCP resources."""
        # List resources
        req_list = {"jsonrpc": "2.0", "id": 7, "method": "resources/list"}
        res_list = self.server.handle_request(req_list)
        resources = res_list["result"]["resources"]
        uris = [r["uri"] for r in resources]
        self.assertIn("vital://snapshot", uris)
        self.assertIn("vital://context/system_upgrade", uris)
        self.assertIn("skills://manual", uris)

        # Read vital://snapshot
        req_read = {
            "jsonrpc": "2.0",
            "id": 8,
            "method": "resources/read",
            "params": {"uri": "vital://snapshot"}
        }
        res_read = self.server.handle_request(req_read)
        contents = res_read["result"]["contents"][0]
        self.assertEqual(contents["uri"], "vital://snapshot")
        snap = json.loads(contents["text"])
        self.assertIn("domains", snap)
        self.assertIn("system_health", snap)

        # Read skills://manual
        req_manual = {
            "jsonrpc": "2.0",
            "id": 9,
            "method": "resources/read",
            "params": {"uri": "skills://manual"}
        }
        res_manual = self.server.handle_request(req_manual)
        manuals = json.loads(res_manual["result"]["contents"][0]["text"])
        self.assertIn("system.rollback", manuals)
        self.assertIn("vital.snapshot", manuals)

    def test_server_discover(self):
        """Test modern MCP 2026-07-28 server/discover capability."""
        req = {
            "jsonrpc": "2.0",
            "id": 10,
            "method": "server/discover"
        }
        res = self.server.handle_request(req)
        self.assertEqual(res["jsonrpc"], "2.0")
        self.assertEqual(res["id"], 10)
        self.assertIn("supportedProtocolVersions", res["result"])
        self.assertIn("2026-07-28", res["result"]["supportedProtocolVersions"])
        self.assertIn("serverInfo", res["result"])

    def test_token_authenticated_execution(self):
        """Test tool execution authenticated with cryptographic DelegationRegistry token."""
        # Grant token to agent
        grant_rec = skills.delegation_registry.grant(
            principal_id="autonomous-security-agent",
            tier=skills.DelegatedAuthorityTier.FULL_DELEGATED_CONTROL,
            scope=["system.rollback"]
        )

        req = {
            "jsonrpc": "2.0",
            "id": 11,
            "method": "tools/call",
            "params": {
                "name": "system.rollback",
                "arguments": {"target_generation": 42, "dry_run": True},
                "_meta": {
                    "caller_id": "autonomous-security-agent",
                    "authorization_token": grant_rec.token
                }
            }
        }
        res = self.server.handle_request(req)
        self.assertFalse(res["result"]["isError"])
        parsed = json.loads(res["result"]["content"][0]["text"])
        self.assertEqual(parsed["status"], "DRY_RUN_PASSED")

        # Verify caller identity mismatch is strictly rejected
        req_spoofed = {
            "jsonrpc": "2.0",
            "id": 12,
            "method": "tools/call",
            "params": {
                "name": "system.rollback",
                "arguments": {"target_generation": 42, "dry_run": True},
                "_meta": {
                    "caller_id": "malicious-spoofed-agent",
                    "authorization_token": grant_rec.token
                }
            }
        }
        res_spoofed = self.server.handle_request(req_spoofed)
        self.assertTrue(res_spoofed["result"]["isError"])
        self.assertIn("Caller identity mismatch", res_spoofed["result"]["content"][0]["text"])

        # Verify stateless modern invocation on fresh server instance without initialize
        fresh_server = McpServer()
        res_stateless = fresh_server.handle_request(req)
        self.assertFalse(res_stateless["result"]["isError"])
        parsed_stateless = json.loads(res_stateless["result"]["content"][0]["text"])
        self.assertEqual(parsed_stateless["status"], "DRY_RUN_PASSED")


if __name__ == "__main__":
    unittest.main()
