"""
Asynchronous Socket Broker and JSON-RPC 2.0 Dispatcher for Conductor Runtime.
Implements the Zero-Idle COLD/WARM/HOT lifecycle and delegated authority routing.
Adheres strictly to SPEC-NRX-CND-018, SPEC-NRX-SKL-019, and SPEC-NRX-CND-021.
"""

import os
import sys
import json
import time
import asyncio
from pathlib import Path
from typing import Dict, Any, Optional, Set

from neuronix_core import skills
from neuronix_core import vital


def resolve_socket_path(override: Optional[str] = None) -> Path:
    """
    Determines the canonical Conductor control socket path.
    Prioritizes explicit arguments, environment variables, XDG runtime dir,
    and user-specific runtime fallbacks.
    """
    if override:
        return Path(override)

    env_path = os.environ.get("CONDUCTOR_SOCKET_PATH")
    if env_path:
        return Path(env_path)

    xdg_runtime = os.environ.get("XDG_RUNTIME_DIR")
    if xdg_runtime and os.path.exists(xdg_runtime):
        return Path(xdg_runtime) / "conductor.sock"

    uid = os.getuid()
    standard_user_run = Path(f"/run/user/{uid}")
    if standard_user_run.exists():
        return standard_user_run / "conductor.sock"

    return Path(f"/tmp/conductor-{uid}.sock")


class LifecycleState:
    COLD = "COLD"
    WARM = "WARM"
    HOT = "HOT"


class ConductorServer:
    """
    Lightweight, zero-idle control broker listening on a UNIX domain socket.
    Exposes canonical NEURONIX capabilities via JSON-RPC 2.0.
    """

    def __init__(self, socket_path: Optional[Path] = None):
        self.socket_path = socket_path or resolve_socket_path()
        self.start_time = time.time()
        self.start_monotonic = time.monotonic_ns()
        self._clients: Set[asyncio.StreamWriter] = set()
        self._gui_attached = False
        self._delegated_authorities: Dict[str, str] = {}
        self._delegated_tokens: Dict[str, str] = {}
        self._pending_proposals: Dict[str, Dict[str, Any]] = {}
        self._resolved_proposals: Dict[str, Dict[str, Any]] = {}
        self._server: Optional[asyncio.AbstractServer] = None
        self._running = False

    @property
    def lifecycle_state(self) -> str:
        if self._gui_attached:
            return LifecycleState.HOT
        if len(self._clients) > 0:
            return LifecycleState.WARM
        return LifecycleState.COLD

    async def start(self):
        """Starts the UNIX domain socket server, supporting authentic systemd socket activation."""
        listen_fds = os.environ.get("LISTEN_FDS")
        listen_pid = os.environ.get("LISTEN_PID")
        self.is_socket_activated = False

        if listen_fds and listen_pid:
            try:
                fds_count = int(listen_fds)
                target_pid = int(listen_pid)
                if fds_count >= 1 and target_pid == os.getpid():
                    import socket
                    # File descriptor 3 is SD_LISTEN_FDS_START
                    sock = socket.fromfd(3, socket.AF_UNIX, socket.SOCK_STREAM)
                    sock.setblocking(False)
                    server_kwargs = {"sock": sock}
                    if sys.version_info >= (3, 13):
                        server_kwargs["cleanup_socket"] = False
                    self._server = await asyncio.start_unix_server(
                        self._handle_client,
                        **server_kwargs
                    )
                    self.is_socket_activated = True
                    self._running = True
                    return
            except Exception as e:
                print(f"Warning: systemd socket activation failed, falling back to path: {e}")

        # Fallback to standalone path-based binding
        self.socket_path.parent.mkdir(parents=True, exist_ok=True)
        if self.socket_path.exists():
            try:
                self.socket_path.unlink()
            except OSError:
                pass

        self._server = await asyncio.start_unix_server(
            self._handle_client,
            path=str(self.socket_path)
        )
        try:
            os.chmod(self.socket_path, 0o600)
        except OSError:
            pass

        self._running = True

    async def stop(self):
        """Stops the socket server and disconnects active clients."""
        self._running = False
        if self._server:
            self._server.close()
            await self._server.wait_closed()

        for writer in list(self._clients):
            try:
                writer.close()
                await writer.wait_closed()
            except Exception:
                pass
        self._clients.clear()

        # Only unlink socket file if NOT socket activated by systemd
        if not getattr(self, "is_socket_activated", False):
            if self.socket_path.exists():
                try:
                    self.socket_path.unlink()
                except OSError:
                    pass

    async def _handle_client(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
        """Processes incoming client connections and dispatches JSON-RPC 2.0 requests."""
        self._clients.add(writer)
        buffer = ""

        try:
            while self._running:
                data = await reader.read(65536)
                if not data:
                    break

                buffer += data.decode("utf-8", errors="replace")
                while "\n" in buffer:
                    line, buffer = buffer.split("\n", 1)
                    line = line.strip()
                    if not line:
                        continue

                    response = await self._process_raw_message(line)
                    if response is not None:
                        response_bytes = (json.dumps(response) + "\n").encode("utf-8")
                        writer.write(response_bytes)
                        await writer.drain()

        except (asyncio.CancelledError, ConnectionResetError, BrokenPipeError):
            pass
        finally:
            self._clients.discard(writer)
            try:
                writer.close()
                await writer.wait_closed()
            except Exception:
                pass

    async def _process_raw_message(self, raw_line: str) -> Optional[Dict[str, Any]]:
        """Parses and dispatches a single JSON-RPC line."""
        try:
            req = json.loads(raw_line)
        except Exception as e:
            return {
                "jsonrpc": "2.0",
                "id": None,
                "error": {
                    "code": -32700,
                    "message": f"Parse error: {str(e)}"
                }
            }

        if not isinstance(req, dict) or req.get("jsonrpc") != "2.0" or "method" not in req:
            return {
                "jsonrpc": "2.0",
                "id": req.get("id") if isinstance(req, dict) else None,
                "error": {
                    "code": -32600,
                    "message": "Invalid Request: missing jsonrpc 2.0 frame or method"
                }
            }

        req_id = req.get("id")
        method = req.get("method")
        params = req.get("params", {})
        if not isinstance(params, dict):
            params = {}

        # Notification handling (no id)
        is_notification = ("id" not in req)

        try:
            result = await self._dispatch_method(method, params)
            if is_notification:
                return None
            return {
                "jsonrpc": "2.0",
                "id": req_id,
                "result": result
            }
        except skills.SkillApprovalRequired as approval_err:
            prop = approval_err.proposal
            if isinstance(prop, dict) and "proposal_hash" in prop:
                self._pending_proposals[prop["proposal_hash"]] = prop
            if is_notification:
                return None
            return {
                "jsonrpc": "2.0",
                "id": req_id,
                "error": {
                    "code": -32002,
                    "message": "Human approval gate required under active delegation policy",
                    "data": approval_err.proposal
                }
            }
        except skills.SkillExecutionError as exec_err:
            if is_notification:
                return None
            return {
                "jsonrpc": "2.0",
                "id": req_id,
                "error": {
                    "code": -32003,
                    "message": str(exec_err)
                }
            }
        except NotImplementedError:
            if is_notification:
                return None
            return {
                "jsonrpc": "2.0",
                "id": req_id,
                "error": {
                    "code": -32601,
                    "message": f"Method not found: {method}"
                }
            }
        except Exception as ex:
            if is_notification:
                return None
            return {
                "jsonrpc": "2.0",
                "id": req_id,
                "error": {
                    "code": -32603,
                    "message": f"Internal error: {str(ex)}"
                }
            }

    async def _dispatch_method(self, method: str, params: Dict[str, Any]) -> Any:
        """Route method execution to specialized subsystem handlers."""
        if method == "conductor.ping":
            return {
                "status": "PONG",
                "lifecycle_state": self.lifecycle_state,
                "active_connections": len(self._clients),
                "uptime_seconds": round(time.time() - self.start_time, 2),
                "monotonic_timestamp_ns": time.monotonic_ns()
            }

        elif method == "conductor.version":
            return {
                "distribution": "NEURONIX OS",
                "version": "1.0.4",
                "protocol_version": "1.0.0",
                "control_socket": str(self.socket_path),
                "capabilities_registered": len(skills.list_skills()),
                "zero_idle_enabled": True
            }

        elif method == "vital.snapshot":
            return vital.snapshot()

        elif method == "vital.subscribe":
            frequency_ms = params.get("frequency_ms", 1000)
            return {
                "subscribed": True,
                "frequency_ms": frequency_ms,
                "stream_id": f"vtl-stream-{time.monotonic_ns()}"
            }

        elif method == "vital.unsubscribe":
            return {"unsubscribed": True}

        elif method == "skills.list":
            return skills.list_skills()

        elif method == "skills.describe":
            skill_id = params.get("skill_id")
            if not skill_id:
                raise skills.SkillExecutionError("Missing 'skill_id' parameter in skills.describe")
            return skills.describe(skill_id)

        elif method == "skills.invoke":
            skill_id = params.get("skill_id")
            if not skill_id:
                raise skills.SkillExecutionError("Missing 'skill_id' parameter in skills.invoke")

            inputs = params.get("inputs", {})
            caller = params.get("caller", "AI_AGENT")
            token = params.get("authorization_token")
            sovereign_override = bool(params.get("sovereign_override", False))

            # Resolve authentic delegation token for agent
            if not token and caller in self._delegated_tokens:
                token = self._delegated_tokens[caller]

            delegated_authority = params.get("delegated_authority") or self._delegated_authorities.get(caller)

            return skills.execute(
                skill_id=skill_id,
                inputs=inputs,
                caller=caller,
                authorization_token=token,
                delegated_authority=delegated_authority,
                sovereign_override=sovereign_override
            )

        elif method == "identity.resolve":
            caller = params.get("caller", "HUMAN_OWNER")
            delegated = self._delegated_authorities.get(caller)
            return {
                "caller": caller,
                "principal": caller.upper(),
                "delegated_tier": delegated or "UNASSIGNED",
                "user_sovereignty_active": True
            }

        elif method == "authority.grant":
            agent_id = params.get("agent_id")
            tier = params.get("tier")
            valid_tiers = [
                skills.DelegatedAuthorityTier.OBSERVE_ONLY,
                skills.DelegatedAuthorityTier.PROPOSE_ONLY,
                skills.DelegatedAuthorityTier.USERSPACE_EXECUTE,
                skills.DelegatedAuthorityTier.PRIVILEGED_EXECUTE,
                skills.DelegatedAuthorityTier.FULL_DELEGATED_CONTROL
            ]
            if not agent_id or tier not in valid_tiers:
                raise skills.SkillExecutionError(f"Invalid grant: agent_id='{agent_id}', tier='{tier}'")

            # Create authentic cryptographic delegation in DelegationRegistry
            grant = skills.grant_delegation(
                principal_id=agent_id,
                tier=tier,
                duration_seconds=86400,
                granted_by="HUMAN_OWNER"
            )
            self._delegated_authorities[agent_id] = tier
            self._delegated_tokens[agent_id] = grant["token"]

            return {
                "agent_id": agent_id,
                "granted_tier": tier,
                "token": grant["token"],
                "delegation_id": grant["delegation_id"],
                "granted_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
            }

        elif method == "authority.revoke":
            agent_id = params.get("agent_id")
            if agent_id in self._delegated_tokens:
                token = self._delegated_tokens.pop(agent_id)
                skills.revoke_delegation(token)
            if agent_id in self._delegated_authorities:
                del self._delegated_authorities[agent_id]
            return {
                "agent_id": agent_id,
                "revoked": True
            }

        elif method == "proposal.resolve":
            p_hash = params.get("proposal_hash")
            if not p_hash:
                raise skills.SkillExecutionError("Missing 'proposal_hash' parameter in proposal.resolve")

            action = params.get("action", "APPROVE").upper()
            caller = params.get("caller", "HUMAN_OPERATOR")
            caller_upper = caller.upper()

            if caller_upper in ["AI_AGENT", "AGENT"]:
                raise skills.SkillExecutionError("Unauthorized: AI agents cannot resolve mutation proposals")

            if p_hash in self._resolved_proposals:
                prev_status = self._resolved_proposals[p_hash].get("status", "RESOLVED")
                raise skills.SkillExecutionError(f"Proposal '{p_hash}' has already been resolved ({prev_status})")

            # Look up proposal in server or global skill store
            proposal = self._pending_proposals.pop(p_hash, None)
            if not proposal and p_hash in skills.get_pending_proposals():
                res_record = skills.resolve_proposal(p_hash, action=action, caller=caller_upper)
                self._resolved_proposals[p_hash] = res_record
                return res_record

            now_iso = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
            resolved_rec = {
                "proposal_hash": p_hash,
                "status": action,
                "resolved_by": caller_upper,
                "resolved_at": now_iso,
                "skill_id": proposal.get("skill_id") if proposal else "system.custom",
                "inputs": proposal.get("inputs", {}) if proposal else {}
            }

            if action == "APPROVE":
                skill_target = proposal.get("skill_id", "*") if proposal else "*"
                exec_grant = skills.grant_delegation(
                    principal_id=f"OPERATOR_APPROVAL_{caller_upper}",
                    tier=skills.DelegatedAuthorityTier.PRIVILEGED_EXECUTE,
                    scope=[skill_target],
                    duration_seconds=300,
                    granted_by=caller_upper
                )
                resolved_rec["execution_token"] = exec_grant.get("token")

            self._resolved_proposals[p_hash] = resolved_rec
            return resolved_rec

        elif method == "surface.state":
            pending_count = len(self._pending_proposals) + len(skills.get_pending_proposals())
            return {
                "lifecycle_state": self.lifecycle_state,
                "gui_attached": self._gui_attached,
                "active_connections": len(self._clients),
                "pending_proposals": pending_count,
                "topbar": "CONDUCTOR [ NEURONIX v1.0.4 ] VITAL o NOMINAL"
            }

        else:
            raise NotImplementedError(f"Method '{method}' not implemented")
