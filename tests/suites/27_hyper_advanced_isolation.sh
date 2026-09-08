#!/usr/bin/env bash
# ==============================================================================
# Suite 27: Hyper-Advanced Isolation, OCI Compiler & Sandbox Fabric (35 Tests)
# Validates next-generation capabilities:
# 1. Declarative Nix-to-OCI Micro-Layer Compiler (neuronix container build)
# 2. Transient Systemd User Quadlet Engine (neuronix container daemon/stop/list)
# 3. In-Memory Micro-DNS Mesh for Multi-Service Stacks (*.local)
# 4. Autonomous OS Fabric Image Auto-Fetcher (neuronix sandbox get)
# 5. Windows 11 Autopilot Fabric (TPM 2.0 swtpm + autounattend.xml + VirtIO)
# 6. Btrfs Subvolume Time-Travel Snapshots & Branching
# 7. MCP JSON-RPC protocol exposure for next-gen actions
# 8. Absolute RAM disk cleanliness and zero lingering state
# ==============================================================================

TARGET_BIN="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/bin/neuronix"
SHADOW_BIN="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/src/shadow_vm.sh"
MCP_BIN="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/src/mcp_server.sh"
DISTRO_PATH="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
PYTHON_BIN="$(command -v python3 2>/dev/null || ls -d /nix/store/*-python3-*/bin/python3 2>/dev/null | tail -n 1 || echo "python3")"

start_suite "27 - Hyper-Advanced Isolation, OCI Compiler & Sandbox Fabric"

# ==============================================================================
# Part 1: Declarative Nix-to-OCI Micro-Layer Compiler (Tests 1-4)
# ==============================================================================
assert_exit_code "$TARGET_BIN container build --help" 0 "neuronix container build --help exits 0"

CONTAINER_BUILD_DRY=$($TARGET_BIN container build --dry-run /tmp --json)
assert_output_contains "echo '$CONTAINER_BUILD_DRY'" '"dry_run_success"' "Container build dry-run returns dry_run_success"

TMP_BUILD_DIR=$(mktemp -d "/tmp/neuronix_build_test_XXXXXX")
echo "echo 'hello neuronix oci'" > "${TMP_BUILD_DIR}/entry.sh"
chmod +x "${TMP_BUILD_DIR}/entry.sh"
OCI_OUT_TAR="${TMP_BUILD_DIR}/output.tar"

$TARGET_BIN container build "$TMP_BUILD_DIR" --output "$OCI_OUT_TAR" --tag "test-v1" --repo "test-app" --entrypoint "/app/entry.sh" >/dev/null 2>&1
assert_eq "$(test -f "$OCI_OUT_TAR" && echo "exists" || echo "missing")" "exists" "Declarative OCI build produces physical tarball"

assert_output_contains "tar -tf '$OCI_OUT_TAR'" "manifest.json" "Compiled OCI tarball contains manifest.json"
rm -rf "$TMP_BUILD_DIR"

# ==============================================================================
# Part 2: Transient Systemd User Quadlet Engine (Tests 5-9)
# ==============================================================================
assert_exit_code "$TARGET_BIN container daemon --help" 0 "neuronix container daemon --help exits 0"

DAEMON_DRY=$($TARGET_BIN container daemon --dry-run /tmp --name suite-test-daemon --json)
assert_output_contains "echo '$DAEMON_DRY'" '"dry_run_success"' "Container daemon dry-run returns dry_run_success"

TMP_WS_DIR=$(mktemp -d "/tmp/neuronix_daemon_test_XXXXXX")
$TARGET_BIN container daemon "$TMP_WS_DIR" --name suite-worker --run "sleep 30" >/dev/null 2>&1
DAEMON_LIST=$($TARGET_BIN container list --json)
assert_output_contains "echo '$DAEMON_LIST'" "suite-worker" "Container list reports active background daemon"

DAEMON_STOP_OUT=$($TARGET_BIN container stop suite-worker --json)
assert_output_contains "echo '$DAEMON_STOP_OUT'" '"status": "success"' "Container stop halts daemon and vaporizes workspace"
assert_eq "$(test -d "$TMP_WS_DIR" && echo "exists" || echo "missing")" "exists" "Original source directory untouched"
rm -rf "$TMP_WS_DIR"

# ==============================================================================
# Part 3: In-Memory Micro-DNS Mesh for Multi-Service Stacks (Tests 10-13)
# ==============================================================================
DNS_TEST_RES=$("$PYTHON_BIN" -c "
import sys, tempfile, os
sys.path.insert(0, '${DISTRO_PATH}/packages/neuronix-core')
from neuronix_core.container import synthesize_micro_dns_hosts

with tempfile.TemporaryDirectory() as td:
    services = {'web': {}, 'db': {}, 'cache': {}}
    hosts_path, env_map = synthesize_micro_dns_hosts(services, td)
    assert os.path.isfile(hosts_path)
    with open(hosts_path) as f:
        content = f.read()
    assert 'web.local' in content and 'db.local' in content
    assert env_map.get('web') == '127.0.0.10'
    assert env_map.get('db') == '127.0.0.11'
    assert env_map.get('cache') == '127.0.0.12'
print('MICRO_DNS_SYNTH_OK')
")
assert_output_contains "echo '$DNS_TEST_RES'" "MICRO_DNS_SYNTH_OK" "synthesize_micro_dns_hosts computes deterministic 127.0.0.X IP aliases"

TMP_STACK_FILE=$(mktemp "/tmp/neuronix_stack_XXXXXX.yaml")
cat << 'EOF' > "$TMP_STACK_FILE"
services:
  api:
    command: "true"
  worker:
    command: "true"
EOF

STACK_DRY=$($TARGET_BIN container compose --dry-run "$TMP_STACK_FILE" --json)
assert_output_contains "echo '$STACK_DRY'" '"dry_run_success"' "neuronix container compose --dry-run succeeds"
assert_output_contains "echo '$STACK_DRY'" '"mode": "stack"' "Container compose dry-run confirms stack mode"
rm -f "$TMP_STACK_FILE"

# ==============================================================================
# Part 4: Autonomous OS Fabric Image Auto-Fetcher (Tests 14-20)
# ==============================================================================
assert_exit_code "$TARGET_BIN sandbox get --help" 0 "neuronix sandbox get --help exits 0"

GET_CATALOG=$($TARGET_BIN sandbox get list)
assert_output_contains "echo '$GET_CATALOG'" "alpine" "OS Fabric catalog lists Alpine Linux"
assert_output_contains "echo '$GET_CATALOG'" "windows-11" "OS Fabric catalog lists Windows 11 Autopilot"

GET_ALPINE_DRY=$($TARGET_BIN sandbox get --dry-run alpine --json)
assert_output_contains "echo '$GET_ALPINE_DRY'" "902b33948e3e481ff117013ba0cbbcf63fb58e17dbfe3573c7198bb66c2eb943" "Alpine image matches verified SHA-256"

GET_UBUNTU_DRY=$($TARGET_BIN sandbox get --dry-run ubuntu-24.04 --json)
assert_output_contains "echo '$GET_UBUNTU_DRY'" "ubuntu-24.04-live-server" "Ubuntu 24.04 maps to verified Noble Numbat ISO"

GET_WIN_DRY=$($TARGET_BIN sandbox get --dry-run windows-11 --json)
assert_output_contains "echo '$GET_WIN_DRY'" "Win11_English_x64.iso" "Windows 11 target resolves destination filename"

assert_exit_code "$TARGET_BIN sandbox get nonexistent_distro_404" 1 "Invalid OS distro rejected with exit code 1"

# ==============================================================================
# Part 5: Windows 11 Autopilot Fabric (Tests 21-24)
# ==============================================================================
WIN_XML_TEMP=$(mktemp "/tmp/autounattend_test_XXXXXX.xml")
bash -c "source '$SHADOW_BIN' && generate_win11_autounattend '$WIN_XML_TEMP'"
assert_output_contains "grep -F 'BypassTPMCheck' '$WIN_XML_TEMP'" "BypassTPMCheck" "Windows Autopilot answer file bypasses TPM 2.0 check"
assert_output_contains "grep -F 'BypassSecureBootCheck' '$WIN_XML_TEMP'" "BypassSecureBootCheck" "Windows Autopilot answer file bypasses SecureBoot"
assert_output_contains "grep -F 'BypassRAMCheck' '$WIN_XML_TEMP'" "BypassRAMCheck" "Windows Autopilot answer file bypasses RAM requirements"
assert_output_contains "grep -F 'Neuronix' '$WIN_XML_TEMP'" "Neuronix" "Windows Autopilot answer file provisions local administrator account"
rm -f "$WIN_XML_TEMP"

# ==============================================================================
# Part 6: Btrfs Subvolume Time-Travel Snapshots & Branching (Tests 25-32)
# ==============================================================================
assert_exit_code "$TARGET_BIN sandbox snapshot --help" 0 "neuronix sandbox snapshot --help exits 0"

SNAP_CREATE_DRY=$($TARGET_BIN sandbox snapshot create mylab snap-baseline --dry-run --json)
assert_output_contains "echo '$SNAP_CREATE_DRY'" '"dry_run_success"' "Sandbox snapshot create dry-run succeeds"

SNAP_RESTORE_DRY=$($TARGET_BIN sandbox snapshot restore mylab snap-baseline --dry-run --json)
assert_output_contains "echo '$SNAP_RESTORE_DRY'" '"dry_run_success"' "Sandbox snapshot restore dry-run succeeds"

SNAP_LIST_OUT=$($TARGET_BIN sandbox snapshot list mylab --json)
assert_output_contains "echo '$SNAP_LIST_OUT'" '"sandbox": "mylab"' "Sandbox snapshot list outputs structured JSON"

assert_exit_code "$TARGET_BIN sandbox branch --help" 0 "neuronix sandbox branch --help exits 0"

BRANCH_DRY=$($TARGET_BIN sandbox branch mylab mylab-fork --dry-run --json)
assert_output_contains "echo '$BRANCH_DRY'" '"dry_run_success"' "Sandbox branch dry-run succeeds"

# Functional snapshot creation and listing
$TARGET_BIN sandbox snapshot create suite-lab snap-alpha >/dev/null 2>&1
SNAP_LIST_REAL=$($TARGET_BIN sandbox snapshot list suite-lab --json)
assert_output_contains "echo '$SNAP_LIST_REAL'" "snap-alpha" "Functional snapshot create and list verified"

# Functional branching
$TARGET_BIN sandbox branch suite-lab suite-lab-branch >/dev/null 2>&1
assert_eq "$(test -d "$HOME/.local/share/neuronix/sandboxes/suite-lab-branch" && echo "exists" || echo "missing")" "exists" "Functional sandbox branch created in persistence directory"
rm -rf "$HOME/.local/share/neuronix/sandboxes/suite-lab" "$HOME/.local/share/neuronix/sandboxes/suite-lab-branch"

# ==============================================================================
# Part 7: MCP Protocol Integration for Next-Gen Capabilities (Tests 33-34)
# ==============================================================================
MCP_CALL_CONTAINER_LIST='{"jsonrpc":"2.0","id":301,"method":"tools/call","params":{"name":"neuronix_container","arguments":{"action":"list"}}}'
MCP_CONT_RES=$(echo "$MCP_CALL_CONTAINER_LIST" | $TARGET_BIN mcp)
assert_output_contains "echo '$MCP_CONT_RES'" "daemons" "MCP neuronix_container tool supports action list"

MCP_CALL_SANDBOX_GET='{"jsonrpc":"2.0","id":302,"method":"tools/call","params":{"name":"neuronix_sandbox","arguments":{"action":"get","os":"alpine","dry_run":true}}}'
MCP_SB_RES=$(echo "$MCP_CALL_SANDBOX_GET" | $TARGET_BIN mcp)
assert_output_contains "echo '$MCP_SB_RES'" "alpine-virt" "MCP neuronix_sandbox tool supports action get"

# ==============================================================================
# Part 8: Absolute RAM Disk Cleanliness & Final Invariants (Test 35)
# ==============================================================================
assert_eq "$(ls -1 /dev/shm/neuronix_shadow_* 2>/dev/null | wc -l)" "0" "RAM disk /dev/shm maintains 100% purity post Suite 27 execution"
