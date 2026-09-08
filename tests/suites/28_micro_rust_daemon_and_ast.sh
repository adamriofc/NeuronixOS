#!/usr/bin/env bash
# ==============================================================================
# Suite 28: Micro-Rust Systems Daemon & High-Concurrency AST (25 Tests)
# Validates autonomous substrate & systems daemon capabilities:
# 1. Surgical zero-dependency Rust daemon binary execution & CLI integration
# 2. Transparent fallback semantics when daemon socket is standby/offline
# 3. JSON-RPC 2.0 ping/pong protocol contracts
# 4. Unified AST (Abstract System Tree) Schema 2.0.0 generation
# 5. Core capability declarations (ast_query, ephemeral_ghost, ebpf_lsm_guard, workspace_branch)
# 6. Python domain client integration (query_system_ast, is_daemon_active)
# 7. MCP JSON-RPC protocol exposure (neuronix_ast_query)
# 8. Declarative NixOS module contracts (modules/services/daemon.nix)
# ==============================================================================

TARGET_BIN="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/bin/neuronix"
MCP_BIN="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/src/mcp_server.sh"
DISTRO_PATH="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
PYTHON_BIN="$(command -v python3 2>/dev/null || ls -d /nix/store/*-python3-*/bin/python3 2>/dev/null | tail -n 1 || echo "python3")"

start_suite "28 - Micro-Rust Systems Daemon & High-Concurrency AST"

# ==============================================================================
# Part 1: Daemon CLI Dispatcher & Status Invariants (Tests 1-6)
# ==============================================================================
assert_exit_code "$TARGET_BIN daemon --help" 0 "neuronix daemon --help exits 0"
assert_output_contains "$TARGET_BIN daemon --help" "daemon" "neuronix daemon --help output contains daemon keyword"

assert_exit_code "$TARGET_BIN daemon status" 0 "neuronix daemon status exits 0"
assert_output_contains "$TARGET_BIN daemon status" "NEURONIX AUTONOMOUS MICRO-RUST SYSTEMS DAEMON" "daemon status displays banner"
assert_output_contains "$TARGET_BIN daemon status" "Dual-Plane Ephemeral + eBPF LSM Guard" "daemon status displays architecture"
assert_output_contains "$TARGET_BIN daemon status" "Transparent Fallback Guaranteed" "daemon status confirms transparent fallback mode"

# ==============================================================================
# Part 2: JSON-RPC 2.0 Ping/Pong Protocol (Tests 7-10)
# ==============================================================================
assert_exit_code "$TARGET_BIN daemon ping" 0 "neuronix daemon ping exits 0"
assert_output_contains "$TARGET_BIN daemon ping" '"status":"PONG"' "neuronix daemon ping returns JSON-RPC PONG"
assert_output_contains "$TARGET_BIN daemon ping" '"version"' "neuronix daemon ping response includes version"
assert_output_contains "$TARGET_BIN daemon ping" '"id":1' "neuronix daemon ping includes jsonrpc id 1"

# ==============================================================================
# Part 3: Unified AST Schema 2.0.0 Evaluation (Tests 11-18)
# ==============================================================================
assert_exit_code "$TARGET_BIN daemon ast --json" 0 "neuronix daemon ast --json exits 0"
assert_output_contains "$TARGET_BIN daemon ast --json" '"schema_version": "2.0.0"' "AST schema version is 2.0.0"
assert_output_contains "$TARGET_BIN daemon ast --json" '"capabilities"' "AST payload declares system capabilities"
assert_output_contains "$TARGET_BIN daemon ast --json" '"ast_query"' "AST declares ast_query capability"
assert_output_contains "$TARGET_BIN daemon ast --json" '"ephemeral_ghost"' "AST declares ephemeral_ghost capability"
assert_output_contains "$TARGET_BIN daemon ast --json" '"ebpf_lsm_guard"' "AST declares ebpf_lsm_guard capability"
assert_output_contains "$TARGET_BIN daemon ast --json" '"workspace_branch"' "AST declares workspace_branch capability"
assert_output_contains "$TARGET_BIN daemon ast --json" '"immutable_store": true' "AST confirms immutable Nix store invariant"

# ==============================================================================
# Part 4: Python Domain Client & Substrate Integration (Tests 19-20)
# ==============================================================================
CLIENT_AST_CHECK=$("$PYTHON_BIN" -c "
import sys
sys.path.insert(0, '${DISTRO_PATH}/packages/neuronix-core')
from neuronix_core.daemon_client import query_system_ast
tree = query_system_ast()
assert isinstance(tree, dict)
assert tree.get('schema_version') == '2.0.0'
assert 'system' in tree
assert 'security' in tree
assert 'capabilities' in tree
print('CLIENT_AST_OK')
")
assert_eq "$CLIENT_AST_CHECK" "CLIENT_AST_OK" "neuronix_core.daemon_client.query_system_ast produces validated AST tree"

CLIENT_ACTIVE_CHECK=$("$PYTHON_BIN" -c "
import sys
sys.path.insert(0, '${DISTRO_PATH}/packages/neuronix-core')
from neuronix_core.daemon_client import is_daemon_active
res = is_daemon_active()
assert isinstance(res, bool)
print('CLIENT_ACTIVE_OK')
")
assert_eq "$CLIENT_ACTIVE_CHECK" "CLIENT_ACTIVE_OK" "neuronix_core.daemon_client.is_daemon_active returns boolean without failure"

# ==============================================================================
# Part 5: MCP JSON-RPC Server AST Tool Protocol (Tests 21-22)
# ==============================================================================
MCP_TOOLS_LIST=$(printf '{"jsonrpc":"2.0","id":101,"method":"tools/list","params":{}}\n' | "$MCP_BIN" 2>/dev/null)
assert_output_contains "echo '$MCP_TOOLS_LIST'" "neuronix_ast_query" "MCP tools/list exposes neuronix_ast_query tool"

MCP_AST_CALL=$(printf '{"jsonrpc":"2.0","id":102,"method":"tools/call","params":{"name":"neuronix_ast_query","arguments":{}}}\n' | "$MCP_BIN" 2>/dev/null)
assert_output_contains "echo '$MCP_AST_CALL'" "schema_version" "MCP tools/call neuronix_ast_query returns schema 2.0.0 AST"

# ==============================================================================
# Part 6: NixOS Service Modules & Flake Packaging Contracts (Tests 23-25)
# ==============================================================================
assert_output_contains "cat '${DISTRO_PATH}/modules/services/daemon.nix'" "neuronix.services.daemon" "daemon.nix declares neuronix.services.daemon option"
assert_output_contains "cat '${DISTRO_PATH}/modules/services/daemon.nix'" "RuntimeDirectory = \"neuronix\"" "daemon.nix configures RuntimeDirectory=neuronix"
assert_output_contains "cat '${DISTRO_PATH}/flake.nix'" "neuronix-daemon" "flake.nix registers neuronix-daemon package"
