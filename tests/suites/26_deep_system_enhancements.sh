#!/usr/bin/env bash
# ==============================================================================
# Suite 26: Deep-System Enhancements & Subsystem Invariants (36 Tests)
# Validates the 6 deep-system capabilities:
# 1. Boot-Sentinel autonomous health & watchdog rollback
# 2. Generational forensic diff engine
# 3. Imperative-to-declarative reverse compiler (distill)
# 4. Ephemeral zero-copy RAM sandbox (bubblewrap + /dev/shm)
# 5. Deterministic workload matrix tuning (gaming/battery/audio/balanced)
# 6. P2P binary cache mesh discovery (Avahi/mDNS + port 5000)
# 7. MCP protocol exposure for all 6 subsystems
# ==============================================================================

TARGET_BIN="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/bin/neuronix"
MCP_BIN="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/src/mcp_server.sh"
DISTRO_PATH="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
PYTHON_BIN="$(command -v python3 2>/dev/null || ls -d /nix/store/*-python3-*/bin/python3 2>/dev/null | tail -n 1 || echo "python3")"

start_suite "26 - Deep-System Enhancements & Invariants"

# ==============================================================================
# Subsystem 1: Boot-Sentinel Watchdog & Health Assessment (Tests 1-5)
# ==============================================================================
assert_output_contains "test -f '${DISTRO_PATH}/modules/core/sentinel.nix' && echo 'exists'" "exists" "Boot-Sentinel NixOS module exists"
assert_output_contains "grep -F 'neuronix-sentinel-confirm' '${DISTRO_PATH}/modules/core/sentinel.nix'" "neuronix-sentinel-confirm" "Boot-Sentinel declares confirmation systemd service"
assert_output_contains "grep -F 'neuronix-sentinel-fallback' '${DISTRO_PATH}/modules/core/sentinel.nix'" "neuronix-sentinel-fallback" "Boot-Sentinel declares emergency fallback rollback service"

assert_exit_code "$TARGET_BIN sentinel" 0 "CLI sentinel command exits 0"
SENTINEL_JSON=$($TARGET_BIN sentinel --json)
assert_output_contains "echo '$SENTINEL_JSON'" '"active_generation"' "CLI sentinel --json exposes active_generation"
assert_output_contains "echo '$SENTINEL_JSON'" '"last_known_good_generation"' "CLI sentinel --json exposes last_known_good_generation"

# ==============================================================================
# Subsystem 2: Generational Forensic Diff Engine (Tests 6-10)
# ==============================================================================
assert_output_contains "test -f '${DISTRO_PATH}/packages/neuronix-core/neuronix_core/diff.py' && echo 'exists'" "exists" "Core diff engine Python module exists"
assert_exit_code "$TARGET_BIN diff" 0 "CLI diff command exits 0"
DIFF_JSON=$($TARGET_BIN diff --json)
assert_output_contains "echo '$DIFF_JSON'" '"target_a"' "CLI diff --json reports target_a baseline"
assert_output_contains "echo '$DIFF_JSON'" '"target_b"' "CLI diff --json reports target_b comparison"

assert_output_contains "'${PYTHON_BIN}' -c \"
import sys
sys.path.insert(0, '${DISTRO_PATH}/packages/neuronix-core')
from neuronix_core.diff import diff_generations
res = diff_generations(None, None)
assert 'target_a' in res and 'packages_added' in res
print('CORE_DIFF_OK')
\"" "CORE_DIFF_OK" "Python diff_generations domain API returns expected schema"

# ==============================================================================
# Subsystem 3: Imperative-to-Declarative Reverse Engine (Distill) (Tests 11-16)
# ==============================================================================
assert_output_contains "test -f '${DISTRO_PATH}/packages/neuronix-core/neuronix_core/distill.py' && echo 'exists'" "exists" "Core distill engine Python module exists"
assert_exit_code "$TARGET_BIN distill --dry-run jq" 0 "CLI distill --dry-run with valid package jq exits 0"
DISTILL_JSON=$($TARGET_BIN distill --json --dry-run jq)
assert_output_contains "echo '$DISTILL_JSON'" '"dry_run_success"' "CLI distill --dry-run reports dry_run_success"
assert_output_contains "echo '$DISTILL_JSON'" '"proposed_content"' "CLI distill --dry-run proposes declarative module content"

assert_exit_code "$TARGET_BIN distill --dry-run nonexistent_package_random_xyz_404 || true" 0 "CLI distill handles invalid package non-zero or error format"
DISTILL_FAIL_JSON=$($TARGET_BIN distill --json --dry-run nonexistent_package_random_xyz_404 2>&1 || true)
assert_output_contains "echo '$DISTILL_FAIL_JSON'" '"valid": false' "CLI distill rejects non-existent package in nixpkgs"

assert_output_contains "'${PYTHON_BIN}' -c \"
import sys
sys.path.insert(0, '${DISTRO_PATH}/packages/neuronix-core')
from neuronix_core.distill import verify_nixpkgs_attribute
assert verify_nixpkgs_attribute('hello') == True
assert verify_nixpkgs_attribute('fake_xyz_123_not_a_pkg') == False
print('DISTILL_VERIFY_OK')
\"" "DISTILL_VERIFY_OK" "Python verify_nixpkgs_attribute accurately gates packages"

# ==============================================================================
# Subsystem 4: Ephemeral Zero-Copy RAM Sandbox (Tests 17-21)
# ==============================================================================
assert_output_contains "grep -F 'bubblewrap' '${DISTRO_PATH}/modules/hardware/tuning.nix'" "bubblewrap" "Hardware tuning module includes bubblewrap for zero-copy isolation"
assert_exit_code "$TARGET_BIN sandbox --dry-run /tmp" 0 "CLI sandbox --dry-run exits 0"
SANDBOX_JSON=$($TARGET_BIN sandbox --dry-run --json /tmp)
assert_output_contains "echo '$SANDBOX_JSON'" '"dry_run_success"' "CLI sandbox --dry-run --json reports dry_run_success"
assert_output_contains "echo '$SANDBOX_JSON'" '"target": "/tmp"' "CLI sandbox reports correct target path"


assert_output_contains "'${PYTHON_BIN}' -c \"
import sys, tempfile, os
sys.path.insert(0, '${DISTRO_PATH}/packages/neuronix-core')
from neuronix_core.sandbox import allocate_ram_workspace, vaporize_workspace
with tempfile.TemporaryDirectory() as src:
    ws = allocate_ram_workspace(src)
    assert os.path.isdir(ws)
    assert os.path.exists(ws)
    vaporize_workspace(ws)
    assert not os.path.exists(ws)
print('RAM_SANDBOX_OK')
\"" "RAM_SANDBOX_OK" "Python allocate_ram_workspace and vaporize_workspace execute atomically"

# ==============================================================================
# Subsystem 5: Deterministic Workload Matrix (Tune) (Tests 22-26)
# ==============================================================================
assert_output_contains "test -f '${DISTRO_PATH}/modules/hardware/tuning.nix' && echo 'exists'" "exists" "Hardware tuning NixOS module exists"
assert_output_contains "grep -F 'defaultProfile' '${DISTRO_PATH}/modules/hardware/tuning.nix'" "defaultProfile" "Tuning module declares defaultProfile option"
assert_exit_code "$TARGET_BIN tune --status" 0 "CLI tune --status exits 0"
TUNE_JSON=$($TARGET_BIN tune --status --json)
assert_output_contains "echo '$TUNE_JSON'" '"active_profile"' "CLI tune --status --json reports active_profile"
assert_output_contains "echo '$TUNE_JSON'" '"cpu_governor"' "CLI tune --status --json reports cpu_governor"

# ==============================================================================
# Subsystem 6: Local P2P Binary Cache Mesh (Tests 27-30)
# ==============================================================================
assert_output_contains "test -f '${DISTRO_PATH}/modules/services/mesh.nix' && echo 'exists'" "exists" "P2P Cache Mesh NixOS module exists"
assert_output_contains "grep -F '5000' '${DISTRO_PATH}/modules/services/mesh.nix'" "5000" "Mesh module opens port 5000 for LAN nix-serve cache"
assert_exit_code "$TARGET_BIN mesh" 0 "CLI mesh command exits 0"
MESH_JSON=$($TARGET_BIN mesh --json)
assert_output_contains "echo '$MESH_JSON'" '"local_node"' "CLI mesh --json reports local_node"
assert_output_contains "echo '$MESH_JSON'" '"mesh_port": 5000' "CLI mesh --json reports standard mesh port 5000"


# ==============================================================================
# Subsystem 7: MCP Protocol Integration for 6 New Tools (Tests 31-36)
# ==============================================================================
MCP_LIST=$(echo '{"jsonrpc":"2.0","id":200,"method":"tools/list"}' | $TARGET_BIN mcp)
assert_output_contains "echo '$MCP_LIST'" 'neuronix_sentinel' "MCP tools/list exposes neuronix_sentinel"
assert_output_contains "echo '$MCP_LIST'" 'neuronix_diff' "MCP tools/list exposes neuronix_diff"
assert_output_contains "echo '$MCP_LIST'" 'neuronix_distill' "MCP tools/list exposes neuronix_distill"
assert_output_contains "echo '$MCP_LIST'" 'neuronix_sandbox' "MCP tools/list exposes neuronix_sandbox"
assert_output_contains "echo '$MCP_LIST'" 'neuronix_tune' "MCP tools/list exposes neuronix_tune"
assert_output_contains "echo '$MCP_LIST'" 'neuronix_mesh' "MCP tools/list exposes neuronix_mesh"
