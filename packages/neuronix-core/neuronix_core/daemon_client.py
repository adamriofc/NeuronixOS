"""
NEURONIX Micro-Rust Systems Daemon Client
Connects to /run/neuronix/ast.sock with transparent Python fallback.
Copyright (c) 2026 NEURONIX Contributors
Licensed under the Apache License, Version 2.0
"""

import os
import json
import socket
from typing import Dict, Any, Optional

DEFAULT_SOCKET_PATHS = [
    "/run/neuronix/ast.sock",
    "/tmp/neuronix_ast.sock"
]

def is_daemon_active() -> bool:
    """Checks whether the micro-Rust systems daemon socket is responsive."""
    for sock_path in DEFAULT_SOCKET_PATHS:
        if os.path.exists(sock_path):
            try:
                s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                s.settimeout(0.5)
                s.connect(sock_path)
                s.sendall(b'{"jsonrpc":"2.0","method":"system/ping","id":1}\n')
                resp = s.recv(1024)
                s.close()
                data = json.loads(resp.decode("utf-8"))
                if data.get("result", {}).get("status") == "PONG":
                    return True
            except Exception:
                pass
    return False

def query_system_ast(timeout: float = 1.0) -> Dict[str, Any]:
    """Queries System State AST from the micro-Rust daemon or falls back to Python probe."""
    for sock_path in DEFAULT_SOCKET_PATHS:
        if os.path.exists(sock_path):
            try:
                s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                s.settimeout(timeout)
                s.connect(sock_path)
                s.sendall(b'{"jsonrpc":"2.0","method":"ast/query","id":1}\n')
                resp_bytes = b""
                while True:
                    chunk = s.recv(4096)
                    if not chunk:
                        break
                    resp_bytes += chunk
                    if b"\n" in chunk:
                        break
                s.close()
                data = json.loads(resp_bytes.decode("utf-8"))
                if "result" in data:
                    return data["result"]
            except Exception:
                pass

    # Pure Python Fallback Probe
    from .doctor import get_sanitized_diagnostics
    diag = get_sanitized_diagnostics()
    return {
        "schema_version": "2.0.0",
        "system": diag.get("system", {}),
        "memory": diag.get("subsystems", {}).get("memory", {}),
        "storage": diag.get("subsystems", {}).get("storage", {}),
        "security": {
            "ebpf_lsm_active": os.path.exists("/sys/kernel/security/lsm"),
            "dual_plane_ephemeral": True,
            "immutable_store": True,
            "fallback_mode": True
        },
        "capabilities": ["ast_query", "ephemeral_ghost", "ebpf_lsm_guard", "workspace_branch", "dual_plane"]
    }
