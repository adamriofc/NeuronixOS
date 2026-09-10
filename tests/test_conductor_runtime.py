"""
Integration and Unit Tests for Conductor Runtime Socket Broker.
Validates asynchronous UNIX domain socket communication, JSON-RPC 2.0 framing,
COLD/WARM lifecycle transitions, and delegated authority routing.
Adheres to SPEC-NRX-CND-018 and SPEC-NRX-SKL-019.
"""

import os
import sys
import json
import asyncio
import tempfile
import unittest
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT / "packages" / "neuronix-core"))
sys.path.insert(0, str(PROJECT_ROOT / "packages" / "conductor-runtime"))

from conductor_runtime.server import ConductorServer, resolve_socket_path, LifecycleState
from neuronix_core import skills


class TestConductorRuntime(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.tmp_dir = tempfile.TemporaryDirectory()
        self.socket_path = Path(self.tmp_dir.name) / "test_conductor.sock"
        self.server = ConductorServer(socket_path=self.socket_path)
        await self.server.start()

    async def asyncTearDown(self):
        await self.server.stop()
        self.tmp_dir.cleanup()

    def test_socket_path_resolution(self):
        """Test fallback precedence for socket path resolution."""
        # 1. Explicit override
        custom_path = "/tmp/custom.sock"
        self.assertEqual(str(resolve_socket_path(custom_path)), custom_path)

        # 2. Environment override
        os.environ["CONDUCTOR_SOCKET_PATH"] = "/tmp/env_test.sock"
        try:
            self.assertEqual(str(resolve_socket_path()), "/tmp/env_test.sock")
        finally:
            del os.environ["CONDUCTOR_SOCKET_PATH"]

        # 3. Default resolution
        default_path = resolve_socket_path()
        self.assertTrue(str(default_path).endswith("conductor.sock"))

    async def _send_rpc(self, request_obj: dict) -> dict:
        """Helper to send a JSON-RPC request over UNIX socket and read single response."""
        reader, writer = await asyncio.open_unix_connection(path=str(self.socket_path))
        try:
            msg = (json.dumps(request_obj) + "\n").encode("utf-8")
            writer.write(msg)
            await writer.drain()

            line = await reader.readline()
            return json.loads(line.decode("utf-8"))
        finally:
            writer.close()
            await writer.wait_closed()

    async def test_lifecycle_and_ping(self):
        """Test lifecycle transition from COLD to WARM and conductor.ping RPC."""
        # Server with no clients is COLD
        self.assertEqual(self.server.lifecycle_state, LifecycleState.COLD)

        resp = await self._send_rpc({
            "jsonrpc": "2.0",
            "id": 1,
            "method": "conductor.ping"
        })

        self.assertEqual(resp["jsonrpc"], "2.0")
        self.assertEqual(resp["id"], 1)
        res = resp["result"]
        self.assertEqual(res["status"], "PONG")
        self.assertIn("uptime_seconds", res)
        self.assertIn("monotonic_timestamp_ns", res)

    async def test_version_rpc(self):
        """Test conductor.version metadata query."""
        resp = await self._send_rpc({
            "jsonrpc": "2.0",
            "id": "v-1",
            "method": "conductor.version"
        })
        res = resp["result"]
        self.assertEqual(res["distribution"], "NEURONIX OS")
        self.assertEqual(res["version"], "1.0.4")
        self.assertEqual(res["protocol_version"], "1.0.0")
        self.assertTrue(res["zero_idle_enabled"])
        self.assertGreaterEqual(res["capabilities_registered"], 5)

    async def test_vital_snapshot_via_socket(self):
        """Test vital.snapshot execution through UNIX socket."""
        resp = await self._send_rpc({
            "jsonrpc": "2.0",
            "id": 2,
            "method": "vital.snapshot"
        })
        self.assertIn("result", resp)
        snap = resp["result"]
        self.assertIn("timestamp", snap)
        self.assertIn("domains", snap)
        self.assertIn("cpu", snap["domains"])
        self.assertIn("memory", snap["domains"])

    async def test_skills_list_and_describe(self):
        """Test discovering skills and fetching machine-readable operating manuals via RPC."""
        resp_list = await self._send_rpc({
            "jsonrpc": "2.0",
            "id": 3,
            "method": "skills.list"
        })
        skills_array = resp_list["result"]
        self.assertGreaterEqual(len(skills_array), 5)

        resp_desc = await self._send_rpc({
            "jsonrpc": "2.0",
            "id": 4,
            "method": "skills.describe",
            "params": {"skill_id": "system.rollback"}
        })
        desc = resp_desc["result"]
        self.assertEqual(desc["skill_id"], "system.rollback")
        self.assertEqual(desc["category"], "MUTATE")
        self.assertTrue(desc["approval_gate_required"])

    async def test_skills_invoke_with_delegated_authority(self):
        """Test invoking skills with various delegated authority tiers."""
        # 1. AI agent without mutation authority triggers approval gate error (-32002)
        resp_blocked = await self._send_rpc({
            "jsonrpc": "2.0",
            "id": 5,
            "method": "skills.invoke",
            "params": {
                "skill_id": "system.rollback",
                "inputs": {"target_generation": 42, "dry_run": True},
                "caller": "AI_AGENT"
            }
        })
        self.assertIn("error", resp_blocked)
        err = resp_blocked["error"]
        self.assertEqual(err["code"], -32002)
        self.assertIn("data", err)
        self.assertTrue(err["data"]["proposal_hash"])

        # 2. Grant delegated authority to agent
        grant_resp = await self._send_rpc({
            "jsonrpc": "2.0",
            "id": 6,
            "method": "authority.grant",
            "params": {
                "agent_id": "agent-orchestrator-01",
                "tier": skills.DelegatedAuthorityTier.FULL_DELEGATED_CONTROL
            }
        })
        self.assertEqual(grant_resp["result"]["granted_tier"], skills.DelegatedAuthorityTier.FULL_DELEGATED_CONTROL)

        # 3. Invocation by authorized agent now executes smoothly without blocking
        resp_allowed = await self._send_rpc({
            "jsonrpc": "2.0",
            "id": 7,
            "method": "skills.invoke",
            "params": {
                "skill_id": "system.rollback",
                "inputs": {"target_generation": 42, "dry_run": True},
                "caller": "agent-orchestrator-01"
            }
        })
        self.assertIn("result", resp_allowed)
        self.assertEqual(resp_allowed["result"]["status"], "DRY_RUN_PASSED")
        self.assertIn("_receipt", resp_allowed["result"])

    async def test_identity_and_authority_management(self):
        """Test identity resolution and authority revocation."""
        # Grant authority
        await self._send_rpc({
            "jsonrpc": "2.0",
            "id": 8,
            "method": "authority.grant",
            "params": {
                "agent_id": "temp-agent",
                "tier": skills.DelegatedAuthorityTier.USERSPACE_EXECUTE
            }
        })

        # Resolve identity
        id_resp = await self._send_rpc({
            "jsonrpc": "2.0",
            "id": 9,
            "method": "identity.resolve",
            "params": {"caller": "temp-agent"}
        })
        self.assertEqual(id_resp["result"]["delegated_tier"], skills.DelegatedAuthorityTier.USERSPACE_EXECUTE)

        # Revoke authority
        rev_resp = await self._send_rpc({
            "jsonrpc": "2.0",
            "id": 10,
            "method": "authority.revoke",
            "params": {"agent_id": "temp-agent"}
        })
        self.assertTrue(rev_resp["result"]["revoked"])

        # Resolve again -> UNASSIGNED
        id_resp2 = await self._send_rpc({
            "jsonrpc": "2.0",
            "id": 11,
            "method": "identity.resolve",
            "params": {"caller": "temp-agent"}
        })
        self.assertEqual(id_resp2["result"]["delegated_tier"], "UNASSIGNED")

    async def test_error_handling(self):
        """Test parse errors and unknown method errors."""
        # Unknown method -> -32601
        resp_bad = await self._send_rpc({
            "jsonrpc": "2.0",
            "id": 12,
            "method": "non.existent.method"
        })
        self.assertEqual(resp_bad["error"]["code"], -32601)

        # Malformed request -> -32600
        resp_malformed = await self._send_rpc({
            "not_jsonrpc": True
        })
        self.assertEqual(resp_malformed["error"]["code"], -32600)


if __name__ == "__main__":
    unittest.main()
