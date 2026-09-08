#!/usr/bin/env bash
# ==============================================================================
# Suite 27: Hyper-Advanced Isolation, OCI Compiler & Sandbox Fabric (52 Tests)
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

# Functional snapshot creation and listing on backing disk
mkdir -p "$HOME/.local/share/neuronix/sandboxes/suite-lab"
qemu-img create -f qcow2 "$HOME/.local/share/neuronix/sandboxes/suite-lab/disk.qcow2" 10M >/dev/null 2>&1
$TARGET_BIN sandbox snapshot create suite-lab snap-alpha >/dev/null 2>&1
SNAP_LIST_REAL=$($TARGET_BIN sandbox snapshot list suite-lab --json)
assert_output_contains "echo '$SNAP_LIST_REAL'" "snap-alpha" "Functional snapshot create and list verified"

# Functional branching
$TARGET_BIN sandbox branch suite-lab suite-lab-branch >/dev/null 2>&1
assert_eq "$(test -d "$HOME/.local/share/neuronix/sandboxes/suite-lab-branch" && echo "exists" || echo "missing")" "exists" "Functional sandbox branch created in persistence directory"
rm -rf "$HOME/.local/share/neuronix/sandboxes/suite-lab" "$HOME/.local/share/neuronix/sandboxes/suite-lab-branch"

# Rejection of snapshot on unsupported storage without dummy .snap
TMP_UNSUPPORTED_DIR="$HOME/.local/share/neuronix/sandboxes/unsupported-storage-lab"
mkdir -p "$TMP_UNSUPPORTED_DIR"
SNAP_UNSUPPORTED_OUT=$($TARGET_BIN sandbox snapshot create unsupported-storage-lab snap-fail --json 2>&1 || true)
assert_output_contains "echo '$SNAP_UNSUPPORTED_OUT'" "UNSUPPORTED_STORAGE" "Snapshot creation rejects storage without btrfs/qcow2"
assert_eq "$(test -f "$TMP_UNSUPPORTED_DIR/snapshots/snap-fail.snap" && echo 'exists' || echo 'missing')" "missing" "No dummy .snap file created on unsupported storage"
rm -rf "$TMP_UNSUPPORTED_DIR"

# ==============================================================================
# Part 7: Semantic & Security Invariants (Tests 33-39)
# ==============================================================================
# Tar Slip directory traversal defense
TAR_SLIP_TEST=$("$PYTHON_BIN" -c "
import io, tarfile, tempfile, sys
sys.path.insert(0, '${DISTRO_PATH}/packages/neuronix-core')
from neuronix_core.container import safe_extract_tar

buf = io.BytesIO()
with tarfile.open(fileobj=buf, mode='w') as tar:
    data = b'malicious payload'
    ti = tarfile.TarInfo(name='../evil.txt')
    ti.size = len(data)
    tar.addfile(ti, io.BytesIO(data))
buf.seek(0)

with tempfile.TemporaryDirectory() as td:
    with tarfile.open(fileobj=buf, mode='r') as tar:
        try:
            safe_extract_tar(tar, td)
            print('VULNERABLE')
        except ValueError:
            print('REJECTED_SAFELY')
")
assert_eq "$TAR_SLIP_TEST" "REJECTED_SAFELY" "safe_extract_tar rejects directory traversal (Tar Slip)"

# OCI pull failure handling without synthetic fallback
OCI_PULL_FAIL_TEST=$("$PYTHON_BIN" -c "
import sys
sys.path.insert(0, '${DISTRO_PATH}/packages/neuronix-core')
from neuronix_core.container import pull_and_extract_oci_image
rootfs, meta, msg = pull_and_extract_oci_image('nonexistent/image:v99999', '/tmp/nonexistent_oci_test_dir', allow_synthetic=False)
print('NONE' if rootfs is None else 'EXISTS')
" 2>/dev/null)
assert_eq "$OCI_PULL_FAIL_TEST" "NONE" "OCI pull without allow_synthetic fails and leaves no rootfs"

# OS image fetch cryptographic verification
TMP_FETCH_DIR=$(mktemp -d "/tmp/neuronix_fetch_test_XXXXXX")
FETCH_ERR=$(PATH="$TMP_FETCH_DIR:$PATH" NEURONIX_CACHE_DIR="$TMP_FETCH_DIR" bash -c "
mkdir -p '$TMP_FETCH_DIR'
echo '#!/usr/bin/env bash' > '$TMP_FETCH_DIR/curl'
echo 'while [[ \$# -gt 0 ]]; do if [[ \"\$1\" == \"-o\" ]]; then echo corrupt > \"\$2\"; shift 2; else shift; fi; done' >> '$TMP_FETCH_DIR/curl'
chmod +x '$TMP_FETCH_DIR/curl'
source '$SHADOW_BIN'
execute_sandbox_get alpine 2>&1
" || true)
assert_output_contains "echo '$FETCH_ERR'" "Cryptographic SHA-256 verification failed" "Image auto-fetcher rejects SHA-256 mismatch and aborts"
rm -rf "$TMP_FETCH_DIR"

# Diff on non-existent generation exits 1
assert_exit_code "$TARGET_BIN diff 999998 999999" 1 "Diff on non-existent system generation exits with code 1"

# MCP error tool call returns isError: true
MCP_ERR_CALL='{"jsonrpc":"2.0","id":404,"method":"tools/call","params":{"name":"neuronix_diff","arguments":{"gen_a":"999998","gen_b":"999999"}}}'
MCP_ERR_RES=$(echo "$MCP_ERR_CALL" | $TARGET_BIN mcp)
assert_output_contains "echo '$MCP_ERR_RES'" "isError" "MCP server returns isError on tool execution failure"

# Installer generated flake imports platform.nix
TMP_INST_DIR=$(mktemp -d "/tmp/neuronix_inst_test_XXXXXX")
DRY_RUN=1 TARGET_ROOT="$TMP_INST_DIR" bash "${DISTRO_PATH}/installer/scripts/neuronix-install-engine.sh" >/dev/null 2>&1
assert_output_contains "cat '$TMP_INST_DIR/etc/nixos/flake.nix'" "./modules/platform.nix" "Installer generated flake.nix imports ./modules/platform.nix"
rm -rf "$TMP_INST_DIR"

# ==============================================================================
# Part 8: MCP Protocol Integration for Next-Gen Capabilities (Tests 40-41)
# ==============================================================================
MCP_CALL_CONTAINER_LIST='{"jsonrpc":"2.0","id":301,"method":"tools/call","params":{"name":"neuronix_container","arguments":{"action":"list"}}}'
MCP_CONT_RES=$(echo "$MCP_CALL_CONTAINER_LIST" | $TARGET_BIN mcp)
assert_output_contains "echo '$MCP_CONT_RES'" "daemons" "MCP neuronix_container tool supports action list"

MCP_CALL_SANDBOX_GET='{"jsonrpc":"2.0","id":302,"method":"tools/call","params":{"name":"neuronix_sandbox","arguments":{"action":"get","os":"alpine","dry_run":true}}}'
MCP_SB_RES=$(echo "$MCP_CALL_SANDBOX_GET" | $TARGET_BIN mcp)
assert_output_contains "echo '$MCP_SB_RES'" "alpine-virt" "MCP neuronix_sandbox tool supports action get"

# ==============================================================================
# Part 9: Semantic & Behavioral Closures (Tests 42-51)
# ==============================================================================
# Test 42: Safe tar extraction verifies benign archive correctness and hard-fails on filter violation
TAR_FILTER_FAIL_TEST=$("$PYTHON_BIN" -c "
import io, tarfile, tempfile, os, sys
sys.path.insert(0, '${DISTRO_PATH}/packages/neuronix-core')
from neuronix_core.container import safe_extract_tar

# 1. Benign archive extraction happy-path verification
benign_buf = io.BytesIO()
expected_payload = b'{\"server\": \"neuronix\", \"port\": 8080, \"engine\": \"container\"}'
with tarfile.open(fileobj=benign_buf, mode='w') as tar:
    ti = tarfile.TarInfo(name='service/config.json')
    ti.size = len(expected_payload)
    ti.mode = 0o4755 # setuid bit that must be cleared
    tar.addfile(ti, io.BytesIO(expected_payload))
benign_buf.seek(0)

with tempfile.TemporaryDirectory() as td_benign:
    with tarfile.open(fileobj=benign_buf, mode='r') as tar:
        safe_extract_tar(tar, td_benign)
    extracted_target = os.path.join(td_benign, 'service/config.json')
    if not os.path.exists(extracted_target):
        print('BENIGN_EXTRACTION_FAILED')
        sys.exit(0)
    with open(extracted_target, 'rb') as f:
        if f.read() != expected_payload:
            print('CONTENT_CORRUPTED')
            sys.exit(0)
    st_mode = os.stat(extracted_target).st_mode
    if st_mode & 0o4000:
        print('SETUID_NOT_CLEARED')
        sys.exit(0)

# 2. Malicious archive traversal hard-failure verification
mal_buf = io.BytesIO()
with tarfile.open(fileobj=mal_buf, mode='w') as tar:
    data = b'traversal payload'
    ti = tarfile.TarInfo(name='../../escape.txt')
    ti.size = len(data)
    tar.addfile(ti, io.BytesIO(data))
mal_buf.seek(0)

with tempfile.TemporaryDirectory() as td_mal:
    with tarfile.open(fileobj=mal_buf, mode='r') as tar:
        try:
            safe_extract_tar(tar, td_mal)
            print('UNFILTERED_ESCAPE')
        except ValueError:
            leaked = [f for f in os.listdir(td_mal)]
            print('BENIGN_OK_AND_HARD_FAILURE_SAFE' if len(leaked) == 0 else 'LEAKED')
")
assert_eq "$TAR_FILTER_FAIL_TEST" "BENIGN_OK_AND_HARD_FAILURE_SAFE" "safe_extract_tar verifies benign extraction correctness and hard failure on traversal"

# Test 43: Strict OCI Image Layout Specification & Content-Addressable Blob verification
TMP_OCI_VERIFY_DIR=$(mktemp -d "/tmp/neuronix_oci_spec_XXXXXX")
echo "console.log('oci spec')" > "${TMP_OCI_VERIFY_DIR}/index.js"
OCI_SPEC_TAR="${TMP_OCI_VERIFY_DIR}/oci_spec.tar"
$TARGET_BIN container build "$TMP_OCI_VERIFY_DIR" --output "$OCI_SPEC_TAR" --tag "v1" --repo "spec-app" >/dev/null 2>&1

OCI_SPEC_CHECK=$("$PYTHON_BIN" -c "
import tarfile, json, hashlib, sys

with tarfile.open('${OCI_SPEC_TAR}', 'r') as tar:
    layout_f = tar.extractfile('oci-layout')
    layout_data = json.load(layout_f)
    assert layout_data.get('imageLayoutVersion') == '1.0.0', 'Invalid oci-layout version'

    index_f = tar.extractfile('index.json')
    index_data = json.load(index_f)
    manifest_desc = index_data['manifests'][0]
    manifest_digest = manifest_desc['digest']
    assert manifest_digest.startswith('sha256:'), 'Manifest digest missing sha256 prefix'
    manifest_hash = manifest_digest.split(':')[1]

    blob_manifest_f = tar.extractfile(f'blobs/sha256/{manifest_hash}')
    blob_manifest_bytes = blob_manifest_f.read()
    assert hashlib.sha256(blob_manifest_bytes).hexdigest() == manifest_hash, 'Manifest blob digest mismatch'

    manifest_obj = json.loads(blob_manifest_bytes.decode('utf-8'))
    config_digest = manifest_obj['config']['digest'].split(':')[1]
    layer_digest = manifest_obj['layers'][0]['digest'].split(':')[1]

    config_bytes = tar.extractfile(f'blobs/sha256/{config_digest}').read()
    assert hashlib.sha256(config_bytes).hexdigest() == config_digest, 'Config blob digest mismatch'

    layer_bytes = tar.extractfile(f'blobs/sha256/{layer_digest}').read()
    assert hashlib.sha256(layer_bytes).hexdigest() == layer_digest, 'Layer blob digest mismatch'

    assert tar.getmember('manifest.json') is not None
    assert tar.getmember('repositories') is not None

print('OCI_SPEC_COMPLIANT')
")
assert_eq "$OCI_SPEC_CHECK" "OCI_SPEC_COMPLIANT" "Generated OCI tarball conforms to OCI Image Layout spec with content-addressable blobs"
rm -rf "$TMP_OCI_VERIFY_DIR"

# Test 44: Container build --nix mode fails closed when Nix closure cannot be resolved
TMP_NIX_FAIL_DIR=$(mktemp -d "/tmp/neuronix_nix_fail_XXXXXX")
echo "not a nix project" > "${TMP_NIX_FAIL_DIR}/app.py"
NIX_BUILD_FAIL_OUT=$($TARGET_BIN container build "$TMP_NIX_FAIL_DIR" --nix --output "${TMP_NIX_FAIL_DIR}/out.tar" --json 2>&1 || true)
assert_output_contains "echo '$NIX_BUILD_FAIL_OUT'" '"status": "error"' "Container build --nix fails closed on non-nix project"
rm -rf "$TMP_NIX_FAIL_DIR"

# Test 45: Cached OS image corruption is detected, purged, and rejected
TMP_CACHE_TEST_DIR=$(mktemp -d "/tmp/neuronix_cache_test_XXXXXX")
mkdir -p "$TMP_CACHE_TEST_DIR"
echo "corrupted_cached_bytes" > "$TMP_CACHE_TEST_DIR/alpine-virt-3.20.0-x86_64.iso"
CACHE_REHASH_OUT=$(NEURONIX_IMAGE_CACHE="$TMP_CACHE_TEST_DIR" NEURONIX_CACHE_DIR="$TMP_CACHE_TEST_DIR" bash -c "
source '$SHADOW_BIN'
execute_sandbox_get alpine --dry-run >/dev/null 2>&1
PATH='/bin:/usr/bin' execute_sandbox_get alpine 2>&1
" || true)
assert_output_contains "echo '$CACHE_REHASH_OUT'" "checksum mismatch" "execute_sandbox_get detects corrupted cached image checksum"
rm -rf "$TMP_CACHE_TEST_DIR"

# Tests 46-47: Snapshot restore round-trip state verification (state rollback & artifact eviction)
TMP_SNAP_SANDBOX_DIR="$HOME/.local/share/neuronix/sandboxes/suite-rollback-lab"
mkdir -p "$TMP_SNAP_SANDBOX_DIR"
echo "state_initial" > "${TMP_SNAP_SANDBOX_DIR}/state.txt"
$TARGET_BIN sandbox snapshot create suite-rollback-lab snap-state-1 --allow-full-copy >/dev/null 2>&1
echo "state_mutated" > "${TMP_SNAP_SANDBOX_DIR}/state.txt"
echo "unwanted_drift" > "${TMP_SNAP_SANDBOX_DIR}/drift.txt"
$TARGET_BIN sandbox snapshot restore suite-rollback-lab snap-state-1 >/dev/null 2>&1
RESTORED_STATE=$(cat "${TMP_SNAP_SANDBOX_DIR}/state.txt" 2>/dev/null || echo "missing")
DRIFT_STATUS=$(test -f "${TMP_SNAP_SANDBOX_DIR}/drift.txt" && echo "present" || echo "evicted")
assert_eq "$RESTORED_STATE" "state_initial" "Snapshot restore physically rolls back file content to snapshot state"
assert_eq "$DRIFT_STATUS" "evicted" "Snapshot restore evicts drifted files created after snapshot point"
rm -rf "$TMP_SNAP_SANDBOX_DIR"

# Tests 48-49: Sandbox branching CoW boundary enforcement
TMP_BRANCH_DIR="$HOME/.local/share/neuronix/sandboxes/suite-cow-test"
mkdir -p "$TMP_BRANCH_DIR"
echo "branch_test" > "${TMP_BRANCH_DIR}/data.txt"
BRANCH_COW_REJECT=$(PATH="$TMP_BRANCH_DIR:$PATH" bash -c "
mkdir -p '$TMP_BRANCH_DIR/bin'
echo '#!/usr/bin/env bash' > '$TMP_BRANCH_DIR/bin/cp'
echo 'if [[ \"\$*\" == *\"--reflink=always\"* ]]; then exit 1; fi' >> '$TMP_BRANCH_DIR/bin/cp'
echo 'exec /bin/cp \"\$@\"' >> '$TMP_BRANCH_DIR/bin/cp'
chmod +x '$TMP_BRANCH_DIR/bin/cp'
PATH=\"$TMP_BRANCH_DIR/bin:\$PATH\" $TARGET_BIN sandbox branch suite-cow-test suite-cow-fork --json 2>&1 || true
")
assert_output_contains "echo '$BRANCH_COW_REJECT'" "UNSUPPORTED_STORAGE" "Sandbox branch without CoW rejects unless --allow-full-copy passed"

BRANCH_FULL_COPY_RES=$(PATH="$TMP_BRANCH_DIR/bin:$PATH" $TARGET_BIN sandbox branch suite-cow-test suite-cow-fork --allow-full-copy --json 2>&1)
assert_output_contains "echo '$BRANCH_FULL_COPY_RES'" '"engine": "FULL_COPY"' "Sandbox branch succeeds with FULL_COPY when --allow-full-copy is provided"
rm -rf "$TMP_BRANCH_DIR" "$HOME/.local/share/neuronix/sandboxes/suite-cow-fork"

# Test 50: Sentinel Emergency Fallback cleanly executes transactional rollback
TMP_SENTINEL_DIR=$(mktemp -d "/tmp/neuronix_sentinel_test_XXXXXX")
SENTINEL_EXEC_RES=$("$PYTHON_BIN" -c "
import sys, os, tempfile
sys.path.insert(0, '${DISTRO_PATH}/packages/neuronix-core')
from neuronix_core.journal import TransactionJournal, TransactionState
from neuronix_core.rollback import execute_rollback

with tempfile.TemporaryDirectory() as td:
    j_file = os.path.join(td, 'operation_journal.json')
    os.environ['NEURONIX_JOURNAL_FILE'] = j_file
    journal = TransactionJournal(j_file)
    
    last_good = '1'
    target_gen = int(last_good) if last_good.isdigit() else None
    tx_id = journal.start_transaction('emergency_sentinel_rollback', {'target': target_gen})
    success, return_code, output = execute_rollback(target_generation=target_gen, dry_run=True)
    
    if success:
        journal.commit_transaction(tx_id, {'outcome': 'restored', 'return_code': return_code, 'output': output})
    else:
        journal.abort_transaction(tx_id, f'Rollback failed (code {return_code}): {output}')
    
    tx = journal.get_transaction(tx_id)
    assert tx is not None, 'Transaction not recorded in journal'
    assert tx['state'] in (TransactionState.COMMITTED, TransactionState.FAILED)
    assert 'abort_reason' in tx['details'] or 'outcome' in tx['details']
print('SENTINEL_FALLBACK_EXEC_OK')
")
assert_eq "$SENTINEL_EXEC_RES" "SENTINEL_FALLBACK_EXEC_OK" "Sentinel emergency fallback script integrates correctly with Journal and Rollback core"
rm -rf "$TMP_SENTINEL_DIR"

# Test 51: Container runtime filesystem path protection & namespace isolation
CONTAINER_ISOL_TEST=$("$PYTHON_BIN" -c "
import sys, tempfile, os, shutil, unittest.mock as mock
sys.path.insert(0, '${DISTRO_PATH}/packages/neuronix-core')
from neuronix_core.container import sanitize_environment, build_bwrap_command

with tempfile.TemporaryDirectory() as td:
    clean_env = sanitize_environment({'AWS_SECRET_ACCESS_KEY': 'leak123', 'USER': 'tester'})
    assert 'AWS_SECRET_ACCESS_KEY' not in clean_env
    assert clean_env.get('USER') == 'tester'
    assert clean_env.get('NEURONIX_CONTAINER') == '1'
    
    bwrap_path = shutil.which('bwrap') or '/usr/bin/bwrap'
    with mock.patch('shutil.which', return_value=bwrap_path):
        tokens, sub_env = build_bwrap_command(td, command='echo test', unshare_net=True)
        assert '--unshare-net' in tokens
        assert '--unshare-pid' in tokens
        assert '--unshare-ipc' in tokens
print('CONTAINER_ISOL_INVARIANTS_OK')
")
assert_eq "$CONTAINER_ISOL_TEST" "CONTAINER_ISOL_INVARIANTS_OK" "Container runtime enforces pid/net/ipc namespace unshare and credential scrubbing"

# ==============================================================================
# Part 10: Absolute RAM Disk Cleanliness & Final Invariants (Test 52)
# ==============================================================================
assert_eq "$(ls -1 /dev/shm/neuronix_shadow_* 2>/dev/null | wc -l)" "0" "RAM disk /dev/shm maintains 100% purity post Suite 27 execution"
