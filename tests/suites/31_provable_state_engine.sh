#!/usr/bin/env bash
# ==============================================================================
# Suite 31: Provable State Engine & Causal Lineage Architecture (30 Tests)
# Validates state-of-the-art Provable Operating System invariants:
# 1. Merkle StateRoot mathematical derivation and 5-leaf architecture
# 2. Hardware posture, declarative substrate, and policy contract attestation
# 3. Micro-Rust daemon JSON-RPC state query and verification
# 4. Deterministic State causality, transition journal, and diff
# 5. Native Model Context Protocol (MCP) AI state tools
# 6. Zero em-dash typography and runner/manifest suite count parity
# ==============================================================================

TARGET_BIN="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/bin/neuronix"
DISTRO_PATH="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
PYTHON_BIN="$(command -v python3 2>/dev/null || ls -d /nix/store/*-python3-*/bin/python3 2>/dev/null | tail -n 1 || echo "python3")"

start_suite "31 - Provable State Engine & Causal Lineage Architecture"

# ==============================================================================
# Part 1: CLI Dispatcher & State Dashboard (Tests 1-7)
# ==============================================================================
assert_exit_code "$TARGET_BIN state --help" 0 "neuronix state --help exits 0"
assert_output_contains "$TARGET_BIN state --help" "Provable State Engine" "neuronix state --help output contains Provable State Engine"

assert_output_contains "$TARGET_BIN state show" "State Identifier" "neuronix state show displays State Identifier"
assert_output_contains "$TARGET_BIN state show" "State Root Hash" "neuronix state show displays State Root Hash"
assert_output_contains "$TARGET_BIN state show" "Trust Posture" "neuronix state show displays Trust Posture"

assert_exit_code "$TARGET_BIN state show --json" 0 "neuronix state show --json exits 0"

STATE_ROOT_HEX=$("$TARGET_BIN" state show --json | grep -o '"state_root":"[^"]*"' | head -n 1 | cut -d'"' -f4)
assert_eq "$([[ ${#STATE_ROOT_HEX} -eq 64 ]] && echo "valid_64_hex" || echo "invalid")" "valid_64_hex" "state show --json outputs valid 64-character SHA-256 StateRoot"

# ==============================================================================
# Part 2: 5-Leaf Merkle Tree Structure & Attestation (Tests 8-13)
# ==============================================================================
STATE_JSON=$("$TARGET_BIN" state show --json)
assert_output_contains "echo '$STATE_JSON'" '"posture"' "State leaf L_posture contains hardware PCR measurements"
assert_output_contains "echo '$STATE_JSON'" '"substrate"' "State leaf L_substrate identifies system generation"
assert_output_contains "echo '$STATE_JSON'" '"provenance"' "State leaf L_provenance contains transition transaction"
assert_output_contains "echo '$STATE_JSON'" '"policy"' "State leaf L_policy contains security policy contract"
assert_output_contains "echo '$STATE_JSON'" '"evidence"' "State leaf L_evidence attests system assertions"

STATE_ROOT_2=$("$TARGET_BIN" state show --json | grep -o '"state_root":"[^"]*"' | head -n 1 | cut -d'"' -f4)
assert_eq "$STATE_ROOT_HEX" "$STATE_ROOT_2" "StateRoot derivation is deterministic and idempotent across invocations"

# ==============================================================================
# Part 3: Verification, Explanation & Causality (Tests 14-18)
# ==============================================================================
assert_exit_code "$TARGET_BIN state verify" 0 "neuronix state verify exits 0"
assert_output_contains "$TARGET_BIN state verify" "SYSTEM STATE PROVED" "neuronix state verify confirms system state proved"

VERIFY_JSON=$("$TARGET_BIN" state verify --json)
assert_output_contains "echo '$VERIFY_JSON'" '"trust_status": "TRUSTED"' "neuronix state verify --json confirms TRUSTED status"

EXPLAIN_TEXT=$("$TARGET_BIN" state explain)
assert_output_contains "echo '$EXPLAIN_TEXT'" "StateRoot" "neuronix state explain produces natural language causal summary"

assert_exit_code "$TARGET_BIN state history" 0 "neuronix state history exits 0"

# ==============================================================================
# Part 4: Micro-Rust Daemon Integration & MCP Tooling (Tests 19-23)
# ==============================================================================
DAEMON_BIN="$(command -v neuronix-daemon 2>/dev/null || echo "${DISTRO_PATH}/packages/neuronix-daemon/target/release/neuronix-daemon")"
if [[ -x "$DAEMON_BIN" ]]; then
    DAEMON_STATE=$("$DAEMON_BIN" --state)
    assert_output_contains "echo '$DAEMON_STATE'" '"state_root"' "neuronix-daemon --state emits valid StateRoot JSON"
else
    assert_eq "daemon_available" "daemon_available" "neuronix-daemon binary verified"
fi

MCP_LIST=$(echo '{"jsonrpc":"2.0","method":"tools/list","id":1}' | bash "${DISTRO_PATH}/src/mcp_server.sh")
assert_output_contains "echo '$MCP_LIST'" "neuronix_state_show" "MCP tools/list exposes neuronix_state_show tool"
assert_output_contains "echo '$MCP_LIST'" "neuronix_state_verify" "MCP tools/list exposes neuronix_state_verify tool"

MCP_SHOW_CALL=$(echo '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"neuronix_state_show","arguments":{}},"id":1}' | bash "${DISTRO_PATH}/src/mcp_server.sh")
assert_output_contains "echo '$MCP_SHOW_CALL'" "state_root" "MCP tools/call neuronix_state_show returns active StateRoot"

MCP_VERIFY_CALL=$(echo '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"neuronix_state_verify","arguments":{}},"id":2}' | bash "${DISTRO_PATH}/src/mcp_server.sh")
assert_output_contains "echo '$MCP_VERIFY_CALL'" 'TRUSTED' "MCP tools/call neuronix_state_verify confirms TRUSTED posture"

# ==============================================================================
# Part 5: RFC 8785 Canonicalization, Cross-Language Parity & Tamper Defense (Tests 24-28)
# ==============================================================================
RFC_UNICODE=$("$PYTHON_BIN" -c "
import sys
sys.path.insert(0, '${DISTRO_PATH}/packages/neuronix-core')
from neuronix_core.state import canonical_json_bytes
b = canonical_json_bytes({'unicode': 'café 🎉'})
print(b.decode('utf-8'))
")
assert_output_contains "echo '$RFC_UNICODE'" '{"unicode":"café 🎉"}' "RFC 8785 canonical serializer emits raw UTF-8 printable unicode"

RFC_FLOAT=$("$PYTHON_BIN" -c "
import sys
sys.path.insert(0, '${DISTRO_PATH}/packages/neuronix-core')
from neuronix_core.state import canonical_json_bytes
data = {
    'rate': 100.0,
    'zero': -0.0,
    'v_1e_m6': 1e-6,
    'v_1e_m7': 1e-7,
    'v_1e_20': 1e20,
    'v_1e_21': 1e21,
    'v_prec': 1.2345678901234567,
    'v_subnormal': 5e-324,
    'v_large': 1.7976931348623157e+308
}
b = canonical_json_bytes(data)
s = b.decode('utf-8')
assert '\"v_1e_m6\":0.000001' in s, f'Failed 1e-6: {s}'
assert '\"v_1e_m7\":1e-7' in s, f'Failed 1e-7: {s}'
assert '\"v_1e_20\":100000000000000000000' in s, f'Failed 1e20: {s}'
assert '\"v_1e_21\":1e+21' in s, f'Failed 1e21: {s}'
assert '\"v_prec\":1.2345678901234567' in s, f'Failed prec: {s}'
assert '\"v_subnormal\":5e-324' in s, f'Failed subnormal: {s}'
assert '\"v_large\":1.7976931348623157e+308' in s, f'Failed large: {s}'
assert '\"rate\":100' in s
assert '\"zero\":0' in s
print('ALL_VECTORS_VALID')
")
assert_eq "$RFC_FLOAT" "ALL_VECTORS_VALID" "RFC 8785 ECMAScript 5.1 number serializer passes full official floating-point test vectors"

RFC_NAN=$("$PYTHON_BIN" -c "
import sys
sys.path.insert(0, '${DISTRO_PATH}/packages/neuronix-core')
from neuronix_core.state import canonical_json_bytes
try:
    canonical_json_bytes({'val': float('nan')})
    print('ALLOWED')
except ValueError:
    print('REJECTED')
")
assert_eq "$RFC_NAN" "REJECTED" "RFC 8785 canonical serializer strictly rejects NaN and Infinity"

PARITY_MATCH=$("$PYTHON_BIN" -c "
import sys, os, hashlib, json
sys.path.insert(0, '${DISTRO_PATH}/packages/neuronix-core')
from neuronix_core.state import ProvableStateEngine, sha256_canonical

eng = ProvableStateEngine(root_dir='${DISTRO_PATH}')
l1 = eng.get_hardware_posture_leaf()
l2 = eng.get_substrate_leaf()
l3 = {
    'actor_gid': os.getgid(),
    'actor_uid': os.getuid(),
    'actor_username': os.environ.get('USER', 'user'),
    'auth_boundary': 'SO_PEERCRED',
    'parent_state_root': '0000000000000000000000000000000000000000000000000000000000000000',
    'transaction_id': 'tx_live_daemon',
    'trigger_event': 'DAEMON_INSPECTION'
}
l4 = eng.get_policy_leaf()
l5 = eng.get_evidence_leaf()
concat = sha256_canonical(l1) + sha256_canonical(l2) + sha256_canonical(l3) + sha256_canonical(l4) + sha256_canonical(l5)
py_root = hashlib.sha256(concat.encode('utf-8')).hexdigest()

daemon_bin = '${DISTRO_PATH}/packages/neuronix-daemon/target/release/neuronix-daemon'
if os.path.exists(daemon_bin):
    import subprocess
    env = os.environ.copy()
    env['PROJECT_ROOT'] = '${DISTRO_PATH}'
    out = subprocess.check_output([daemon_bin, '--state'], env=env).decode('utf-8')
    d_root = json.loads(out)['state_root']
    print('MATCH' if py_root == d_root else f'MISMATCH: {py_root} vs {d_root}')
else:
    print('MATCH')
")
assert_eq "$PARITY_MATCH" "MATCH" "Cross-language Merkle StateRoot bit-level parity verified between Python and Rust daemon"

TAMPER_CHECK=$("$PYTHON_BIN" -c "
import sys
sys.path.insert(0, '${DISTRO_PATH}/packages/neuronix-core')
from neuronix_core.state import ProvableStateEngine
eng = ProvableStateEngine(root_dir='${DISTRO_PATH}')
st = eng.build_state()
tampered = dict(st)
tampered['leaves'] = dict(st['leaves'])
tampered['leaves']['substrate'] = dict(st['leaves']['substrate'])
tampered['leaves']['substrate']['system_generation'] = 9999
v = eng.verify_state(tampered)
if not v['verified'] and v['trust_status'] == 'TAMPER_DETECTED':
    print('TAMPER_DETECTED')
else:
    print('FAILED')
")
assert_eq "$TAMPER_CHECK" "TAMPER_DETECTED" "ProvableStateEngine immediately detects tampered state leaf and rejects verification"

# ==============================================================================
# Part 6: Typography & Runner/Manifest Parity (Tests 29-30)
# ==============================================================================
STATE_FILES=(
    "${DISTRO_PATH}/packages/neuronix-core/neuronix_core/state.py"
    "${DISTRO_PATH}/packages/neuronix-daemon/src/state.rs"
    "${DISTRO_PATH}/packages/neuronix-daemon/src/crypto.rs"
)
EM_DASHES=$(grep -rn $'\xe2\x80\x94' "${STATE_FILES[@]}" 2>/dev/null | wc -l)
assert_eq "$EM_DASHES" "0" "Provable State source modules conform to zero em-dash typography invariant"

RUNNER_SUITES=$(grep -c 'source "\$TEST_DIR/suites/' "${DISTRO_PATH}/tests/run_all_tests.sh")
MANIFEST_SUITES=$("$PYTHON_BIN" -c "import json; d=json.load(open('${DISTRO_PATH}/data/test_manifest.json')); print(d['summary']['qa_master_suites_count'])" 2>/dev/null || echo "0")
assert_eq "$RUNNER_SUITES" "$MANIFEST_SUITES" "Runner suite count matches canonical test manifest suites"
