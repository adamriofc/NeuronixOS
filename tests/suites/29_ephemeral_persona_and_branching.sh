#!/usr/bin/env bash
# ==============================================================================
# Suite 29: Ephemeral Persona, Workspace Branching & eBPF LSM Gate (25 Tests)
# Validates next-gen resilience & security primitives:
# 1. Ephemeral Ghost RAM sessions (zero disk footprint, instant vaporization)
# 2. Ephemeral environment variable injection and isolation
# 3. Volatile RAM cleanliness guarantees (/dev/shm purity)
# 4. Atomic Btrfs / Reflink workspace branching, listing, and revert
# 5. Declarative eBPF LSM policy compilation and kernel security gate
# 6. MCP JSON-RPC protocol exposure for ghost execution and workspace branching
# 7. Declarative NixOS security module contracts (modules/security/ebpf-lsm.nix)
# ==============================================================================

TARGET_BIN="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/bin/neuronix"
MCP_BIN="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/src/mcp_server.sh"
DISTRO_PATH="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
PYTHON_BIN="$(command -v python3 2>/dev/null || ls -d /nix/store/*-python3-*/bin/python3 2>/dev/null | tail -n 1 || echo "python3")"

start_suite "29 - Ephemeral Persona, Workspace Branching & eBPF LSM Gate"

# ==============================================================================
# Part 1: Ephemeral Ghost Persona Execution & RAM Vaporization (Tests 1-8)
# ==============================================================================
assert_exit_code "$TARGET_BIN ghost --help" 0 "neuronix ghost --help exits 0"
assert_output_contains "$TARGET_BIN ghost --help" "ghost" "neuronix ghost --help output contains ghost keyword"

assert_exit_code "$TARGET_BIN ghost --run 'echo GHOST_OK'" 0 "neuronix ghost --run echo exits 0"
assert_output_contains "$TARGET_BIN ghost --run 'echo GHOST_OK'" "GHOST_OK" "ghost command output contains GHOST_OK"
assert_output_contains "$TARGET_BIN ghost --run 'echo GHOST_OK'" "vaporized" "ghost run confirms buffer vaporized"
assert_output_contains "$TARGET_BIN ghost --run 'echo GHOST_OK'" "Zero bytes retained" "ghost run confirms zero bytes retained"

GHOST_ENV_OUT=$($TARGET_BIN ghost --run 'echo "ENV_GHOST=$NEURONIX_GHOST_MODE"')
assert_output_contains "echo '$GHOST_ENV_OUT'" "ENV_GHOST=1" "ghost session injects NEURONIX_GHOST_MODE=1 into child environment"

RAM_LEAK_COUNT=$(ls -1d /dev/shm/neuronix_ghost_* 2>/dev/null | wc -l)
assert_eq "$RAM_LEAK_COUNT" "0" "RAM disk /dev/shm has zero lingering ghost session directories"

# ==============================================================================
# Part 2: Workspace Branching & Storage Reflink Operations (Tests 9-16)
# ==============================================================================
assert_exit_code "$TARGET_BIN branch" 0 "neuronix branch shows usage and exits 0"
assert_output_contains "$TARGET_BIN branch" "branch" "neuronix branch output contains branch keyword"

assert_exit_code "$TARGET_BIN branch list ." 0 "neuronix branch list . exits 0"
assert_output_contains "$TARGET_BIN branch list ." "branches" "neuronix branch list output contains branches key"

STORAGE_PYTHON_CHECK=$("$PYTHON_BIN" -c "
import sys, tempfile, os
sys.path.insert(0, '${DISTRO_PATH}/packages/neuronix-core')
from neuronix_core.storage import is_btrfs_path, create_workspace_branch, list_workspace_branches, revert_workspace_branch

with tempfile.TemporaryDirectory() as td:
    btrfs_flag = is_btrfs_path(td)
    assert isinstance(btrfs_flag, bool)
    
    # Create test file
    test_f = os.path.join(td, 'hello.txt')
    with open(test_f, 'w') as f:
        f.write('initial')
        
    branch_res = create_workspace_branch(td, 'test_branch')
    assert isinstance(branch_res, dict)
    assert branch_res.get('status') == 'SUCCESS'
    
    branches = list_workspace_branches(td)
    assert 'test_branch' in branches
    
    # Mutate file
    with open(test_f, 'w') as f:
        f.write('mutated')
        
    revert_res = revert_workspace_branch(td, 'test_branch')
    assert isinstance(revert_res, dict)
    assert revert_res.get('status') == 'SUCCESS'
    
    with open(test_f, 'r') as f:
        content = f.read()
    assert content == 'initial'
print('STORAGE_BRANCH_ALL_OK')
")
assert_output_contains "echo '$STORAGE_PYTHON_CHECK'" "STORAGE_BRANCH_ALL_OK" "storage branch creation, listing, and revert verify end-to-end"

# Temporary workspace branch CLI test
TMP_WS=$(mktemp -d "/tmp/neuronix_ws_branch_XXXXXX")
echo "original content" > "${TMP_WS}/data.txt"
$TARGET_BIN branch create "$TMP_WS" "v1_checkpoint" >/dev/null 2>&1
WS_LIST_RES=$($TARGET_BIN branch list "$TMP_WS")
assert_output_contains "echo '$WS_LIST_RES'" "v1_checkpoint" "neuronix branch list confirms created branch checkpoint"

echo "modified content" > "${TMP_WS}/data.txt"
$TARGET_BIN branch revert "$TMP_WS" "v1_checkpoint" >/dev/null 2>&1
RESTORED_TEXT=$(cat "${TMP_WS}/data.txt")
assert_eq "$RESTORED_TEXT" "original content" "neuronix branch revert successfully restores workspace data"
rm -rf "$TMP_WS"

# ==============================================================================
# Part 3: Declarative eBPF LSM Gate & Policy Generation (Tests 17-22)
# ==============================================================================
assert_exit_code "$TARGET_BIN ebpf status" 0 "neuronix ebpf status exits 0"
assert_output_contains "$TARGET_BIN ebpf status" "NEURONIX DECLARATIVE eBPF LSM CONTAINER GATE" "ebpf status displays header"
assert_output_contains "$TARGET_BIN ebpf status" "eBPF LSM Status" "ebpf status displays LSM status"

assert_exit_code "$TARGET_BIN ebpf policy curl" 0 "neuronix ebpf policy curl exits 0"
assert_output_contains "$TARGET_BIN ebpf policy curl" '"package":"curl"' "ebpf policy curl contains package curl"
assert_output_contains "$TARGET_BIN ebpf policy curl" "enforced_paths" "ebpf policy contains enforced_paths"

# ==============================================================================
# Part 4: Security Module & Flake Contracts (Tests 23-24)
# ==============================================================================
assert_output_contains "cat '${DISTRO_PATH}/modules/security/ebpf-lsm.nix'" "neuronix.security.ebpfLsm" "ebpf-lsm.nix declares neuronix.security.ebpfLsm option"
assert_output_contains "cat '${DISTRO_PATH}/flake.nix'" "ebpfLsm" "flake.nix exports nixosModules.ebpfLsm"

# ==============================================================================
# Part 5: MCP JSON-RPC Server Integration (Tests 24-25)
# ==============================================================================
MCP_GHOST_CALL=$(printf '{"jsonrpc":"2.0","id":103,"method":"tools/call","params":{"name":"neuronix_ghost_exec","arguments":{"command":"echo MCP_GHOST_PASSED"}}}\n' | "$MCP_BIN" 2>/dev/null)
assert_output_contains "echo '$MCP_GHOST_CALL'" "MCP_GHOST_PASSED" "MCP tools/call neuronix_ghost_exec executes in RAM and returns output"

MCP_BRANCH_CALL=$(printf '{"jsonrpc":"2.0","id":104,"method":"tools/call","params":{"name":"neuronix_workspace_branch","arguments":{"action":"list","path":"."}}}\n' | "$MCP_BIN" 2>/dev/null)
assert_output_contains "echo '$MCP_BRANCH_CALL'" "branches" "MCP tools/call neuronix_workspace_branch returns branches list"

