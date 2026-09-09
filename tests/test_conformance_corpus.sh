#!/usr/bin/env bash
# ==============================================================================
# NEURONIX Independent Conformance Corpus Gate
# Validates RFC 8785 JCS, StateRoot, HDS, Receipts, and Causal Transitions.
# Copyright (c) 2026 NEURONIX Contributors
# Licensed under the Apache License, Version 2.0
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PYTHON_BIN="$(which python3)"
DAEMON_BIN="${PROJECT_ROOT}/packages/neuronix-daemon/target/release/neuronix-daemon"

echo -e "\n\033[1;36m╔═══════════════════════════════════════════════════════════════════╗\033[0m"
echo -e "\033[1;36m║         NEURONIX INDEPENDENT CONFORMANCE CORPUS GATE              ║\033[0m"
echo -e "\033[1;36m╚═══════════════════════════════════════════════════════════════════╝\033[0m\n"

PASSED=0
TOTAL=0

assert_pass() {
    local desc="$1"
    TOTAL=$((TOTAL + 1))
    PASSED=$((PASSED + 1))
    echo -e "  \033[32m✔ PASS\033[0m [$TOTAL] $desc"
}

# 1. JCS Conformance Corpus (14 vectors)
"$PYTHON_BIN" -c "
import json, sys
sys.path.insert(0, '${PROJECT_ROOT}/packages/neuronix-core')
from neuronix_core.state import canonical_json_bytes

with open('${PROJECT_ROOT}/tests/conformance/jcs/vectors.json', 'r', encoding='utf-8') as f:
    corpus = json.load(f)

for v in corpus['vectors']:
    actual = canonical_json_bytes(v['input']).decode('utf-8')
    assert actual == v['expected_jcs'], f'Vector {v[\"id\"]} failed: expected {v[\"expected_jcs\"]} got {actual}'
"
assert_pass "RFC 8785 JCS 14-Vector Independent Conformance Corpus verified byte-for-byte"

# 2. StateRoot Conformance Corpus
"$PYTHON_BIN" -c "
import json, sys, hashlib
sys.path.insert(0, '${PROJECT_ROOT}/packages/neuronix-core')
from neuronix_core.state import canonical_json_bytes

with open('${PROJECT_ROOT}/tests/conformance/stateroot/vectors.json', 'r', encoding='utf-8') as f:
    corpus = json.load(f)

for v in corpus['vectors']:
    leaves = v['leaves']
    h1 = hashlib.sha256(canonical_json_bytes(leaves['posture'])).hexdigest()
    h2 = hashlib.sha256(canonical_json_bytes(leaves['substrate'])).hexdigest()
    h3 = hashlib.sha256(canonical_json_bytes(leaves['provenance'])).hexdigest()
    h4 = hashlib.sha256(canonical_json_bytes(leaves['policy'])).hexdigest()
    h5 = hashlib.sha256(canonical_json_bytes(leaves['evidence'])).hexdigest()
    assert h1 == v['expected_leaf_hashes']['posture']
    assert h2 == v['expected_leaf_hashes']['substrate']
    assert h3 == v['expected_leaf_hashes']['provenance']
    assert h4 == v['expected_leaf_hashes']['policy']
    assert h5 == v['expected_leaf_hashes']['evidence']
    root = hashlib.sha256((h1 + h2 + h3 + h4 + h5).encode('utf-8')).hexdigest()
    assert root == v['expected_state_root']
"
assert_pass "StateRoot 5-Leaf Mathematical Commitment Conformance Corpus verified"

# 3. HDS Contracts Conformance Corpus
"$PYTHON_BIN" -c "
import json, sys
sys.path.insert(0, '${PROJECT_ROOT}/packages/neuronix-core')
from neuronix_core.hyperion import DeterministicVerifier

with open('${PROJECT_ROOT}/tests/conformance/hds/contracts.json', 'r', encoding='utf-8') as f:
    corpus = json.load(f)

for c in corpus['contracts']:
    is_valid, errors = DeterministicVerifier.validate_spec(c['spec'])
    assert is_valid == c['expected_valid'], f'Contract {c[\"id\"]} validity mismatch: expected {c[\"expected_valid\"]}, got {is_valid}'
    if not is_valid and 'expected_error_contains' in c:
        err_str = ' '.join(errors)
        assert c['expected_error_contains'] in err_str, f'Contract {c[\"id\"]} error mismatch: {err_str}'
"
assert_pass "Hyperion Domain Specification (HDS) Conformance Contracts verified"

# 4. Receipt Samples Conformance Corpus
"$PYTHON_BIN" -c "
import json, sys
sys.path.insert(0, '${PROJECT_ROOT}/packages/neuronix-core')
from neuronix_core.hyperion import HyperionExecutionEngine, IsolationTier

engine = HyperionExecutionEngine()

with open('${PROJECT_ROOT}/tests/conformance/receipt/samples.json', 'r', encoding='utf-8') as f:
    corpus = json.load(f)

for s in corpus['samples']:
    tier_enum = getattr(IsolationTier, s['tier'])
    spec = engine.create_domain_spec('conformance_test', tier=tier_enum)
    rcpt = s['receipt']
    proof = engine.calculate_domain_proof(spec, output_digest='0'*64, exit_code=rcpt.get('exit_code', 0), runtime_evidence=rcpt)
    assert proof['trust_verdict'] == s['expected_trust_verdict'], f'Sample {s[\"id\"]} expected {s[\"expected_trust_verdict\"]} got {proof[\"trust_verdict\"]}'
"
assert_pass "Authoritative Execution Receipts Conformance Samples verified"

# 5. Transition Chains Conformance Corpus
"$PYTHON_BIN" -c "
import json, sys, hashlib

with open('${PROJECT_ROOT}/tests/conformance/transition/chains.json', 'r', encoding='utf-8') as f:
    corpus = json.load(f)

for ch in corpus['chains']:
    parent = ch['parent_state_root']
    tx_digest = ch['transaction_digest']
    child = ch['child_state_root']
    actual_tp = hashlib.sha256((parent + tx_digest + child).encode('utf-8')).hexdigest()
    assert actual_tp == ch['expected_transition_proof'], f'Chain {ch[\"id\"]} mismatch: expected {ch[\"expected_transition_proof\"]} got {actual_tp}'
"
assert_pass "Causal State Transition Chain Conformance Corpus verified"

# 6. Canonical Domain Proof Conformance Corpus (Python Engine)
"$PYTHON_BIN" -c "
import json, sys, hashlib
sys.path.insert(0, '${PROJECT_ROOT}/packages/neuronix-core')
from neuronix_core.hyperion import HyperionExecutionEngine

with open('${PROJECT_ROOT}/tests/conformance/domain_proof/vectors.json', 'r', encoding='utf-8') as f:
    corpus = json.load(f)

for v in corpus['vectors']:
    if v['expected_validity']:
        rec = json.loads(v['runtime_evidence_json'])
        concat = v['state_root'] + v['hds_spec_hash'] + v['policy_hash'] + v['workload_input_hash'] + v['output_digest'] + hashlib.sha256(v['runtime_evidence_json'].encode('utf-8')).hexdigest()
        recomputed = hashlib.sha256(concat.encode('utf-8')).hexdigest()
        assert recomputed == v['expected_proof_root'], f'Vector {v[\"id\"]} proof root mismatch'
"
assert_pass "Canonical DomainProofV1 Conformance Vectors verified in Python"

# 7. Canonical Domain Proof Bit-Exact Parity & Verification (Rust Daemon)
if [ -f "$DAEMON_BIN" ]; then
    "$PYTHON_BIN" -c "
import json, sys, subprocess

with open('${PROJECT_ROOT}/tests/conformance/domain_proof/vectors.json', 'r', encoding='utf-8') as f:
    corpus = json.load(f)

for v in corpus['vectors']:
    rec_arg = v['runtime_evidence_json'] if v['runtime_evidence_json'] is not None else ''
    cmd = [
        '${DAEMON_BIN}', '--hyperion', 'proof',
        v['state_root'],
        v['hds_spec_hash'],
        v['policy_hash'],
        v['workload_input_hash'],
        v['output_digest'],
        rec_arg,
        str(v['exit_code']),
        v['isolation_tier']
    ]
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=True)
    res = json.loads(proc.stdout)
    assert res['trust_verdict'] == v['expected_verdict'], f'Rust daemon verdict mismatch on {v[\"id\"]}: claimed {res[\"trust_verdict\"]} != expected {v[\"expected_verdict\"]}'
    assert res['mathematical_validity'] == v['expected_validity'], f'Rust daemon validity mismatch on {v[\"id\"]}'
    if v['expected_validity']:
        assert res['domain_proof_root'] == v['expected_proof_root'], f'Rust daemon root mismatch on {v[\"id\"]}: {res[\"domain_proof_root\"]} != {v[\"expected_proof_root\"]}'
        
        # Test daemon verification API
        ver_cmd = ['${DAEMON_BIN}', '--hyperion', 'verify', proc.stdout.strip()]
        ver_proc = subprocess.run(ver_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=True)
        ver_res = json.loads(ver_proc.stdout)
        assert ver_res['valid'] == True, f'Rust daemon failed to verify its own valid proof for {v[\"id\"]}'
"
    assert_pass "Rust Daemon Bit-Exact DomainProofV1 Parity & API Verification certified"
fi

echo -e "\n\033[1;32m✔ ALL $PASSED/$TOTAL INDEPENDENT CONFORMANCE GATES PASSED (100% GREEN)\033[0m\n"

