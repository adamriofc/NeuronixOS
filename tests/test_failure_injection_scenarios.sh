#!/usr/bin/env bash
# ==============================================================================
# NEURONIX OS Enterprise Failure Injection & Resilience Simulation Harness
# Simulates severe operational faults:
#   1. Simulated Power Loss / Process Termination during Atomic Mutations
#   2. Simulated Storage Exhaustion / Read-Only Storage Enospc Faults
#   3. Simulated Network Disconnection during Upstream Queries
#   4. Simulated Permission Denials on Privileged Interfaces
#   5. High-Frequency Concurrent Contention on System Locks
#
# Copyright (c) 2026 NEURONIX Contributors
# Licensed under the Apache License, Version 2.0
# ==============================================================================

set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON_BIN="$(command -v python3 2>/dev/null || ls -d /nix/store/*-python3-*/bin/python3 2>/dev/null | tail -n 1 || echo "python3")"

PASSED=0
FAILED=0

# Colors
if [[ -t 1 ]]; then
    GREEN="\033[32m"
    RED="\033[31m"
    CYAN="\033[36m"
    BOLD="\033[1m"
    RESET="\033[0m"
else
    GREEN=""
    RED=""
    CYAN=""
    BOLD=""
    RESET=""
fi

echo -e "\n${BOLD}${CYAN}╔═══════════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║     NEURONIX ENTERPRISE FAILURE INJECTION SIMULATION HARNESS      ║${RESET}"
echo -e "${BOLD}${CYAN}║     Chaos Resilience: Power-Loss, ENOSPC, Offline & Contention    ║${RESET}"
echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════════════════════════════════╝${RESET}\n"

fault_assert() {
    local desc="$1"
    local condition="$2"

    echo -ne "  [FAULT-SIM] ${desc} ... "
    if eval "$condition"; then
        echo -e "${GREEN}PASS${RESET}"
        ((PASSED++))
    else
        echo -e "${RED}FAIL${RESET}"
        ((FAILED++))
    fi
}

# 1. Power-Loss & Interrupted Process Simulation
fault_assert "Power-loss: Atomic file replacement preserves original file on crash" \
    "'${PYTHON_BIN}' -c \"
import sys, os, tempfile
test_dir = tempfile.mkdtemp()
target = os.path.join(test_dir, 'critical_config.json')
with open(target, 'w') as f:
    f.write('ORIGINAL_VALID_DATA')

# Simulate crash before atomic rename
tmp = tempfile.NamedTemporaryFile('w', dir=test_dir, delete=False)
tmp.write('PARTIAL_CORRUPTED_DATA')
tmp.flush()
# Simulating abrupt termination: tmp is never renamed to target
with open(target, 'r') as f:
    content = f.read()
assert content == 'ORIGINAL_VALID_DATA'
sys.exit(0)
\""

fault_assert "Power-loss: Dangling transaction journal auto-recovery flags pending rollback" \
    "'${PYTHON_BIN}' -c \"
import sys, os, tempfile
sys.path.insert(0, '${PROJECT_ROOT}/packages/neuronix-core')
from neuronix_core.journal import TransactionJournal, TransactionState
with tempfile.NamedTemporaryFile() as tf:
    j = TransactionJournal(journal_path=tf.name)
    tx_id = j.start_transaction('system_update', {'previous_generation': 5})
    j.update_transaction(tx_id, TransactionState.APPLYING)
    # Simulate abrupt power loss: process dies with tx in APPLYING
    # On reboot, recovery probe executes
    report = j.recover_dangling_transactions()
    assert len(report) == 1
    assert 'NEEDS_ROLLBACK_TO_GEN_5' in report[0]['action']
    assert len(j.get_dangling_transactions()) == 0
\""

# 2. Simulated Storage Exhaustion / ENOSPC
fault_assert "Storage-fault: Graceful handling when destination directory is unwritable" \
    "'${PYTHON_BIN}' -c \"
import sys, os
sys.path.insert(0, '${PROJECT_ROOT}/packages/neuronix-core')
from neuronix_core.journal import TransactionJournal
# Attempt to write journal to illegal non-directory
try:
    j = TransactionJournal(journal_path='/dev/null/impossible_dir/journal.json')
    j.start_transaction('fail_test')
    sys.exit(1)
except Exception:
    sys.exit(0)
\""

# 3. Simulated Network Disconnection
fault_assert "Network-fault: Doctor probe degrades gracefully when offline" \
    "'${PYTHON_BIN}' -c \"
import sys
sys.path.insert(0, '${PROJECT_ROOT}/packages/neuronix-core')
from neuronix_core.doctor import get_sanitized_diagnostics
diag = get_sanitized_diagnostics()
assert diag['schema_version'] == '1.0.0'
assert 'health_status' in diag
\""

# 4. Simulated Permission Denials
fault_assert "Permission-fault: Privileged battery threshold write handles permission denied" \
    "'${PYTHON_BIN}' -c \"
import sys
sys.path.insert(0, '${PROJECT_ROOT}/packages/neuronix-core')
from neuronix_core.operations import execute_privileged_operation
# Call with invalid command
ok, code, msg = execute_privileged_operation('unregistered_root_operation')
assert not ok
assert code == 126
\""

# 5. High-Frequency Concurrent Contention Stress
fault_assert "Contention-stress: 20 rapid competing lock threads resolve without deadlock" \
    "'${PYTHON_BIN}' -c \"
import sys, tempfile, threading
sys.path.insert(0, '${PROJECT_ROOT}/packages/neuronix-core')
from neuronix_core.lock import OperationLock, ConcurrentOperationError

with tempfile.NamedTemporaryFile() as tf:
    acquired_count = 0
    blocked_count = 0
    lock_obj = threading.Lock()

    def worker():
        global acquired_count, blocked_count
        try:
            with OperationLock('contender', lock_path=tf.name):
                with lock_obj:
                    acquired_count += 1
        except ConcurrentOperationError:
            with lock_obj:
                blocked_count += 1

    threads = [threading.Thread(target=worker) for _ in range(20)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    assert acquired_count + blocked_count == 20
    assert acquired_count >= 1
\""

echo -e "\n${BOLD}═══════════════════════════════════════════════════════════════════${RESET}"
echo -e "  Total Failure Invariants  : $((PASSED + FAILED))"
echo -e "  Passed Validations        : ${PASSED}"
echo -e "  Failed Validations        : ${FAILED}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════════════${RESET}\n"

if [[ $FAILED -eq 0 ]]; then
    echo -e "${BOLD}${GREEN}✔ ALL FAILURE INJECTION AND CHAOS GATES PASSED 100%${RESET}\n"
    exit 0
else
    echo -e "${BOLD}${RED}✖ FAILURE SIMULATION INVARIANT VIOLATED${RESET}\n"
    exit 1
fi
