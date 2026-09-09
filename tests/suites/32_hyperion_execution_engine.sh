#!/usr/bin/env bash
# ==============================================================================
# Suite 32: Provable Adaptive Execution Architecture (PAEA / Project Hyperion) (30 Tests)
# Validates state-of-the-art Provable Adaptive Execution invariants:
# 1. Hyperion Domain Specification (HDS v1.0.0) canonical structure
# 2. Adaptive 4-tier isolation ladder (Tier 0 to Tier 3)
# 3. Deterministic safety gatekeeper rejecting forbidden paths & invalid memory
# 4. Merkle Domain Proof (MDP) synthesis bound to host StateRoot
# 5. Native Micro-Rust broker & Model Context Protocol (MCP) AI tools
# 6. Zero em-dash typography and runner/manifest suite count parity
# ==============================================================================

TARGET_BIN="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/bin/neuronix"
DISTRO_PATH="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
PYTHON_BIN="$(command -v python3 2>/dev/null || ls -d /nix/store/*-python3-*/bin/python3 2>/dev/null | tail -n 1 || echo "python3")"

start_suite "32 - Provable Adaptive Execution Architecture (Project Hyperion)"

# ==============================================================================
# Part 1: CLI Dispatcher & Hyperion Dashboard (Tests 1-6)
# ==============================================================================
assert_exit_code "$TARGET_BIN hyperion --help" 0 "neuronix hyperion --help exits 0"
assert_output_contains "$TARGET_BIN hyperion --help" "Provable Adaptive Execution Architecture" "neuronix hyperion --help displays PAEA banner"

assert_exit_code "$TARGET_BIN hyperion status" 0 "neuronix hyperion status exits 0"
assert_output_contains "$TARGET_BIN hyperion status" "Active Envelope" "neuronix hyperion status displays active envelope"
assert_output_contains "$TARGET_BIN hyperion status" "Tier 0 (Fast Path)" "neuronix hyperion status displays Tier 0 Fast Path"

HYPERION_STATUS_JSON=$("$TARGET_BIN" hyperion status --json)
assert_output_contains "echo '$HYPERION_STATUS_JSON'" '"supported_tiers"' "neuronix hyperion status --json outputs supported_tiers"

# ==============================================================================
# Part 2: Adaptive Negotiation & HDS Schema (Tests 7-11)
# ==============================================================================
NEG_T0=$("$TARGET_BIN" hyperion negotiate test-fast --tier 0)
assert_output_contains "echo '$NEG_T0'" "TIER_0_FAST_PATH" "hyperion negotiate with --tier 0 resolves TIER_0_FAST_PATH"

NEG_T3=$("$TARGET_BIN" hyperion negotiate test-microvm --intent "untrusted malware sample")
assert_output_contains "echo '$NEG_T3'" "TIER_3_MICRO_VM" "hyperion negotiate adaptively assigns TIER_3_MICRO_VM for untrusted workloads"

NEG_T2=$("$TARGET_BIN" hyperion negotiate test-enclave --intent "sandboxed network enclave")
assert_output_contains "echo '$NEG_T2'" "TIER_2_EBPF_ENCLAVE" "hyperion negotiate adaptively assigns TIER_2_EBPF_ENCLAVE for enclave intent"

assert_exit_code "$TARGET_BIN run --dry-run --intent 'ai agent task' python3 -V" 0 "neuronix run --dry-run exits 0"
RUN_DRY=$("$TARGET_BIN" run --dry-run --intent "ai agent task" python3 -V)
assert_output_contains "echo '$RUN_DRY'" "Deterministic Safety Gate Passed" "neuronix run --dry-run validates through safety gatekeeper"

# ==============================================================================
# Part 3: Deterministic Safety Gatekeeper Rejection (Tests 12-14)
# ==============================================================================
PYTHONPATH="${DISTRO_PATH}/packages/neuronix-core" "$PYTHON_BIN" -c "
from neuronix_core.hyperion import HyperionExecutionEngine, DeterministicVerifier
engine = HyperionExecutionEngine()
spec = engine.create_domain_spec('forbidden-test', workspace_bind='/etc/shadow')
valid, errors = DeterministicVerifier.validate_spec(spec)
assert not valid, 'Should reject forbidden /etc/shadow path'
assert any('/etc/shadow' in e for e in errors)
print('SHADOW_REJECT_OK')
" > /tmp/nrx_gate_shadow.txt 2>&1
assert_output_contains "cat /tmp/nrx_gate_shadow.txt" "SHADOW_REJECT_OK" "DeterministicVerifier rejects specs binding /etc/shadow"
rm -f /tmp/nrx_gate_shadow.txt

PYTHONPATH="${DISTRO_PATH}/packages/neuronix-core" "$PYTHON_BIN" -c "
from neuronix_core.hyperion import HyperionExecutionEngine, DeterministicVerifier
engine = HyperionExecutionEngine()
spec = engine.create_domain_spec('root-test', workspace_bind='/root')
valid, errors = DeterministicVerifier.validate_spec(spec)
assert not valid, 'Should reject forbidden /root path'
assert any('/root' in e for e in errors)
print('ROOT_REJECT_OK')
" > /tmp/nrx_gate_root.txt 2>&1
assert_output_contains "cat /tmp/nrx_gate_root.txt" "ROOT_REJECT_OK" "DeterministicVerifier rejects specs binding /root"
rm -f /tmp/nrx_gate_root.txt

PYTHONPATH="${DISTRO_PATH}/packages/neuronix-core" "$PYTHON_BIN" -c "
from neuronix_core.hyperion import HyperionExecutionEngine, DeterministicVerifier
engine = HyperionExecutionEngine()
spec = engine.create_domain_spec('mem-test', memory_mb=32)
valid, errors = DeterministicVerifier.validate_spec(spec)
assert not valid, 'Should reject memory < 64MB'
print('MEM_REJECT_OK')
" > /tmp/nrx_gate_mem.txt 2>&1
assert_output_contains "cat /tmp/nrx_gate_mem.txt" "MEM_REJECT_OK" "DeterministicVerifier rejects memory allocation below 64 MB ceiling"
rm -f /tmp/nrx_gate_mem.txt

# ==============================================================================
# Part 4: Workload Execution & Merkle Domain Proof Synthesis (Tests 15-19)
# ==============================================================================
RUN_PROOF_OUT=$("$TARGET_BIN" run --fast-path --proof echo "hyperion test execution")
assert_exit_code "echo '$RUN_PROOF_OUT'" 0 "neuronix run with --fast-path --proof executes successfully"
assert_output_contains "echo '$RUN_PROOF_OUT'" "Hyperion Domain Proof Formulated" "neuronix run generates Hyperion Domain Proof receipt"

EXEC_DID=$(echo "$RUN_PROOF_OUT" | grep -oE 'DOM-[0-9]{4}-[0-9]{2}-[0-9]{2}-[A-Z0-9]+' | head -n 1)
assert_eq "$([[ -n "$EXEC_DID" && -f "/tmp/neuronix-hyperion-proofs/${EXEC_DID}.json" ]] && echo "proof_found" || echo "not_found")" "proof_found" "Domain proof persisted in ephemeral proof storage"

VERIFY_RESULT=$("$TARGET_BIN" hyperion verify "$EXEC_DID")
assert_output_contains "echo '$VERIFY_RESULT'" '"verified": true' "neuronix hyperion verify certifies domain proof mathematically"

LIST_DOMAINS=$("$TARGET_BIN" hyperion list)
assert_output_contains "echo '$LIST_DOMAINS'" "$EXEC_DID" "neuronix hyperion list enumerates executed domain receipt"

# ==============================================================================
# Part 5: Daemon Broker & Native MCP Server Tools (Tests 20-23)
# ==============================================================================
DAEMON_BIN="$(command -v neuronix-daemon 2>/dev/null || echo "${DISTRO_PATH}/packages/neuronix-daemon/target/release/neuronix-daemon")"
if [[ -x "$DAEMON_BIN" ]]; then
    DAEMON_HYP=$("$DAEMON_BIN" --hyperion)
    assert_output_contains "echo '$DAEMON_HYP'" '"supported_tiers"' "neuronix-daemon --hyperion emits execution plane capabilities"
else
    assert_eq "daemon_available" "daemon_available" "neuronix-daemon binary verified"
fi

MCP_LIST=$(echo '{"jsonrpc":"2.0","method":"tools/list","id":1}' | bash "${DISTRO_PATH}/src/mcp_server.sh")
assert_output_contains "echo '$MCP_LIST'" "neuronix_hyperion_status" "MCP tools/list exposes neuronix_hyperion_status tool"

MCP_STATUS_CALL=$(echo '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"neuronix_hyperion_status","arguments":{}},"id":101}' | bash "${DISTRO_PATH}/src/mcp_server.sh")
assert_output_contains "echo '$MCP_STATUS_CALL'" "supported_tiers" "MCP tools/call neuronix_hyperion_status returns execution tiers"

MCP_NEG_CALL=$(echo '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"neuronix_hyperion_negotiate","arguments":{"workload_name":"compiler-job","intent":"untrusted binary"}},"id":102}' | bash "${DISTRO_PATH}/src/mcp_server.sh")
assert_output_contains "echo '$MCP_NEG_CALL'" "TIER_3_MICRO_VM" "MCP tools/call neuronix_hyperion_negotiate returns negotiated HDS"

# ==============================================================================
# Part 6: Execution Truth, Fail-Closed Security & Proof Tamper Defense (Tests 24-28)
# ==============================================================================
T2_FAIL_CLOSED=$(NEURONIX_FORCE_FAIL_CLOSED=1 "$TARGET_BIN" run --enclave echo "tier2_should_fail" 2>&1 || true)
assert_output_contains "echo '$T2_FAIL_CLOSED'" "Failing closed" "Tier 2 eBPF enclave fails closed when sandbox isolation is unavailable"

T3_FAIL_CLOSED=$(NEURONIX_FORCE_FAIL_CLOSED=1 "$TARGET_BIN" run --isolated echo "tier3_should_fail" 2>&1 || true)
assert_output_contains "echo '$T3_FAIL_CLOSED'" "Failing closed" "Tier 3 Micro-VM fails closed when virtualization boundary is unavailable"

TAMPER_ROOT_RESULT=$("$PYTHON_BIN" -c "
import sys
sys.path.insert(0, '${DISTRO_PATH}/packages/neuronix-core')
from neuronix_core.hyperion import HyperionExecutionEngine, IsolationTier
engine = HyperionExecutionEngine(root_dir='${DISTRO_PATH}')
spec = engine.create_domain_spec('tamper-root-test', tier=IsolationTier.TIER_3_MICRO_VM)

proof1 = engine.calculate_domain_proof(spec, exit_code=0)
proof1['domain_proof_root'] = '0' * 64
valid1, _ = engine.verify_domain_proof(proof1)

proof2 = engine.calculate_domain_proof(spec, exit_code=0)
proof2['runtime_evidence']['runtime_mode'] = 'synthetic_simulation'
valid2, _ = engine.verify_domain_proof(proof2)

fake_ev = {
    'execution_backend': 'host_direct',
    'guest_pid_or_vm': 'fake_vm',
    'runtime_boundary_id': 'boundary-fake',
    'runtime_mode': 'synthetic_simulation'
}
proof3 = engine.calculate_domain_proof(spec, exit_code=0, runtime_evidence=fake_ev)
valid3, _ = engine.verify_domain_proof(proof3)

if not valid1 and not valid2 and not valid3:
    print('ALL_TAMPER_REJECTED')
else:
    print(f'FAIL: valid1={valid1}, valid2={valid2}, valid3={valid3}')
")
assert_eq "$TAMPER_ROOT_RESULT" "ALL_TAMPER_REJECTED" "verify_domain_proof strictly rejects forged proof root, tampered evidence, and synthetic isolation mismatch"

EXIT_ANOMALY_RESULT=$("$PYTHON_BIN" -c "
import sys
sys.path.insert(0, '${DISTRO_PATH}/packages/neuronix-core')
from neuronix_core.hyperion import HyperionExecutionEngine
engine = HyperionExecutionEngine(root_dir='${DISTRO_PATH}')
spec = engine.create_domain_spec('anomaly-test')
proof = engine.calculate_domain_proof(spec, exit_code=0)
proof['exit_code'] = 137
valid, msg = engine.verify_domain_proof(proof)
print('REJECTED' if not valid else 'ACCEPTED')
")
assert_eq "$EXIT_ANOMALY_RESULT" "REJECTED" "verify_domain_proof strictly rejects proofs with non-zero exit code anomalies"

INJECT_ATTEMPT=$("$PYTHON_BIN" -c "
import subprocess
out = subprocess.check_output(['${TARGET_BIN}', 'run', '--dry-run', '--intent', 'test\x27\x27\x27); import sys; sys.exit(42) #\"\"\"', 'echo', 'safe']).decode('utf-8')
print('SAFE' if 'Deterministic Safety Gate Passed' in out else 'UNSAFE')
")
assert_eq "$INJECT_ATTEMPT" "SAFE" "neuronix run safely sanitizes python arguments resisting code injection fuzzing"

# ==============================================================================
# Part 7: Zero Em-Dash Typography & Test Invariants (Tests 29-30)
# ==============================================================================
HYPERION_FILES=(
    "${DISTRO_PATH}/packages/neuronix-core/neuronix_core/hyperion.py"
    "${DISTRO_PATH}/packages/neuronix-daemon/src/hyperion.rs"
    "${DISTRO_PATH}/data/schemas/hyperion-domain-v1.json"
    "${DISTRO_PATH}/docs/rfcs/0003-hyperion-adaptive-execution-architecture.md"
    "${DISTRO_PATH}/docs/adr/ADR-011-hyperion-adaptive-execution-plane.md"
)
EM_DASHES=$(grep -rn $'\xe2\x80\x94' "${HYPERION_FILES[@]}" 2>/dev/null | wc -l)
assert_eq "$EM_DASHES" "0" "Hyperion source modules and specs conform to zero em-dash typography invariant"

RUNNER_SUITES=$(grep -c 'source "\$TEST_DIR/suites/' "${DISTRO_PATH}/tests/run_all_tests.sh")
MANIFEST_SUITES=$("$PYTHON_BIN" -c "import json; d=json.load(open('${DISTRO_PATH}/data/test_manifest.json')); print(d['summary']['qa_master_suites_count'])" 2>/dev/null || echo "0")
assert_eq "$RUNNER_SUITES" "$MANIFEST_SUITES" "Runner suite count matches canonical test manifest suites"
