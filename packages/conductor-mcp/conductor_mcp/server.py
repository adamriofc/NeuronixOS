"""
Model Context Protocol (MCP 2026-07-28) Server for Conductor.
Exposes canonical NEURONIX Skills as MCP tools and Vital observations as MCP resources.
Adheres strictly to SPEC-NRX-CND-018, SPEC-NRX-SKL-019, and SPEC-NRX-CND-021.
"""

import sys
import json
from typing import Dict, Any, Optional, List

from neuronix_core import skills
from neuronix_core import vital


class McpServer:
    """
    Stateless, high-performance MCP server implementing protocol versions
    2024-11-05 and 2026-07-28.
    """

    def __init__(self):
        self.server_info = {
            "name": "conductor-mcp",
            "version": "1.0.5"
        }
        self.negotiated_version = "2026-07-28"

    def handle_request(self, req: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """Handles a single JSON-RPC 2.0 MCP request frame."""
        if not isinstance(req, dict) or req.get("jsonrpc") != "2.0":
            return {
                "jsonrpc": "2.0",
                "id": req.get("id") if isinstance(req, dict) else None,
                "error": {"code": -32600, "message": "Invalid JSON-RPC frame"}
            }

        req_id = req.get("id")
        method = req.get("method")
        params = req.get("params", {})
        if not isinstance(params, dict):
            params = {}

        is_notification = ("id" not in req)

        if method == "notifications/initialized":
            return None

        try:
            result = self._dispatch(method, params)
            if is_notification:
                return None
            return {
                "jsonrpc": "2.0",
                "id": req_id,
                "result": result
            }
        except Exception as e:
            if is_notification:
                return None
            return {
                "jsonrpc": "2.0",
                "id": req_id,
                "error": {"code": -32603, "message": str(e)}
            }

    def _dispatch(self, method: str, params: Dict[str, Any]) -> Any:
        if method == "initialize":
            client_version = params.get("protocolVersion")
            if client_version == "2026-07-28":
                raise ValueError("MCP 2026-07-28 is stateless and does not support initialize. Use server/discover and self-describing per-request _meta.")
            if client_version in ["2024-11-05", "2025-03-26"]:
                self.negotiated_version = client_version
                return {
                    "protocolVersion": self.negotiated_version,
                    "capabilities": {
                        "tools": {"listChanged": False},
                        "resources": {"subscribe": False, "listChanged": False},
                        "logging": {},
                        "tasks": {}
                    },
                    "serverInfo": self.server_info
                }
            raise ValueError(f"Unsupported legacy protocolVersion '{client_version}'")

        elif method == "ping":
            return {}

        elif method == "server/discover":
            return {
                "serverInfo": self.server_info,
                "supportedProtocolVersions": ["2024-11-05", "2025-03-26", "2026-07-28"],
                "capabilities": {
                    "tools": {"listChanged": False},
                    "resources": {"subscribe": False, "listChanged": False},
                    "logging": {},
                    "tasks": {}
                }
            }

        elif method == "tools/list":
            skill_list = skills.list_skills()
            mcp_tools = []
            for s in skill_list:
                desc = (
                    f"{s.get('title', s['skill_id'])}: {s.get('description', '')}\n"
                    f"[Category: {s.get('category')}, Approval Gate: {s.get('approval_gate_required')}]"
                )
                mcp_tools.append({
                    "name": s["skill_id"],
                    "description": desc,
                    "inputSchema": s.get("inputs_schema", {"type": "object"})
                })
            return {"tools": mcp_tools}

        elif method == "tools/call":
            tool_name = params.get("name")
            arguments = params.get("arguments", {})
            meta = params.get("_meta", {})

            if "protocolVersion" in meta:
                proto = meta["protocolVersion"]
                if proto not in ["2024-11-05", "2025-03-26", "2026-07-28"]:
                    raise ValueError(f"Invalid or unsupported protocolVersion in _meta: '{proto}'")

            # Enforce caller="AI_AGENT" and sovereign authorization token validation.
            # Never trust caller-asserted delegated_authority from unauthenticated agent payload.
            token = meta.get("authorization_token")
            caller_id = meta.get("caller_id")

            if token and caller_id:
                grant = skills.delegation_registry.validate_token(token, tool_name)
                if grant and grant.principal_id != caller_id:
                    return {
                        "content": [
                            {
                                "type": "text",
                                "text": f"SKILL_EXECUTION_ERROR: Caller identity mismatch: token issued to '{grant.principal_id}', but caller claimed '{caller_id}'"
                            }
                        ],
                        "isError": True
                    }

            try:
                res = skills.execute(
                    skill_id=tool_name,
                    inputs=arguments,
                    caller="AI_AGENT",
                    authorization_token=token
                )
                return {
                    "content": [
                        {
                            "type": "text",
                            "text": json.dumps(res, indent=2)
                        }
                    ],
                    "isError": False
                }
            except skills.SkillApprovalRequired as approval_err:
                prop = approval_err.proposal
                return {
                    "content": [
                        {
                            "type": "text",
                            "text": (
                                f"APPROVAL_REQUIRED: Operation '{tool_name}' requires human confirmation.\n"
                                f"Proposal Hash: {prop.get('proposal_hash')}\n"
                                f"Severity: {prop.get('severity')}\n"
                                f"Details: {json.dumps(prop, indent=2)}"
                            )
                        }
                    ],
                    "isError": True
                }
            except skills.SkillExecutionError as exec_err:
                return {
                    "content": [
                        {
                            "type": "text",
                            "text": f"SKILL_EXECUTION_ERROR: {str(exec_err)}"
                        }
                    ],
                    "isError": True
                }

        elif method == "resources/list":
            return {
                "resources": [
                    {
                        "uri": "vital://snapshot",
                        "name": "Live Vital Telemetry Snapshot",
                        "description": "Laboratory-grade machine observation snapshot.",
                        "mimeType": "application/json"
                    },
                    {
                        "uri": "vital://context/system_upgrade",
                        "name": "Vital Upgrade Context Package",
                        "description": "Tailored context for system upgrade or rollback reasoning.",
                        "mimeType": "application/json"
                    },
                    {
                        "uri": "vital://context/diagnostic",
                        "name": "Vital Diagnostic Context Package",
                        "description": "Tailored context for performance and fault diagnosis.",
                        "mimeType": "application/json"
                    },
                    {
                        "uri": "skills://manual",
                        "name": "NEURONIX Skill Operating Manual",
                        "description": "Full machine-readable operating manual for all capabilities.",
                        "mimeType": "application/json"
                    }
                ]
            }

        elif method == "resources/read":
            uri = params.get("uri", "")
            if uri == "vital://snapshot":
                data = vital.snapshot()
            elif uri == "vital://context/system_upgrade":
                data = vital.context("system_upgrade")
            elif uri == "vital://context/diagnostic":
                data = vital.context("diagnostic")
            elif uri == "skills://manual":
                data = {s["skill_id"]: skills.describe(s["skill_id"]) for s in skills.list_skills()}
            else:
                raise ValueError(f"Unknown resource URI: {uri}")

            return {
                "contents": [
                    {
                        "uri": uri,
                        "mimeType": "application/json",
                        "text": json.dumps(data, indent=2)
                    }
                ]
            }

        else:
            raise NotImplementedError(f"Unsupported MCP method: {method}")


def main():
    """Stdio entrypoint for Conductor MCP server."""
    server = McpServer()
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except Exception as e:
            err_frame = {
                "jsonrpc": "2.0",
                "id": None,
                "error": {"code": -32700, "message": f"Parse error: {str(e)}"}
            }
            sys.stdout.write(json.dumps(err_frame) + "\n")
            sys.stdout.flush()
            continue

        resp = server.handle_request(req)
        if resp is not None:
            sys.stdout.write(json.dumps(resp) + "\n")
            sys.stdout.flush()


if __name__ == "__main__":
    main()
