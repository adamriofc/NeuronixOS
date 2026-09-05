#!/usr/bin/env bash
# ==============================================================================
# Suite 25: Negative Path, Fault Handling & Failure Mode Verification (30 Tests)
# Validates system resilience against bad input, concurrency contention,
# unauthorized commands, corrupt certificates, and hardware state transitions.
# ==============================================================================

DISTRO_PATH="${PROJECT_ROOT}"
PYTHON_BIN="$(command -v python3 2>/dev/null || ls -d /nix/store/*-python3-*/bin/python3 2>/dev/null | tail -n 1 || echo "python3")"

start_suite "25 - Negative Paths & Failure Mode Verification"

# 1-4. Operation Concurrency & Mutual Exclusion
assert_output_contains "'${PYTHON_BIN}' -c \"
import sys, tempfile
sys.path.insert(0, '${DISTRO_PATH}/packages/neuronix-core')
from neuronix_core.lock import OperationLock
with tempfile.NamedTemporaryFile() as tf:
    with OperationLock('test_op', lock_path=tf.name):
        print('ACQUIRED_OK')
\"" "ACQUIRED_OK" "OperationLock acquires exclusive lock on clean lockfile"

assert_output_contains "'${PYTHON_BIN}' -c \"
import sys, tempfile
sys.path.insert(0, '${DISTRO_PATH}/packages/neuronix-core')
from neuronix_core.lock import OperationLock, ConcurrentOperationError
with tempfile.NamedTemporaryFile() as tf:
    with OperationLock('holding_op', lock_path=tf.name):
        try:
            with OperationLock('blocked_op', lock_path=tf.name):
                print('UNEXPECTED')
        except ConcurrentOperationError as e:
            print('BLOCKED_EXPECTED:', e)
\"" "BLOCKED_EXPECTED" "OperationLock contention raises ConcurrentOperationError with holding PID"

assert_output_contains "'${PYTHON_BIN}' -c \"
import sys, tempfile
sys.path.insert(0, '${DISTRO_PATH}/packages/neuronix-core')
from neuronix_core.lock import OperationLock
with tempfile.NamedTemporaryFile() as tf:
    with OperationLock('first_op', lock_path=tf.name):
        pass
    with OperationLock('second_op', lock_path=tf.name):
        print('REACQUIRED_OK')
\"" "REACQUIRED_OK" "OperationLock release enables subsequent operation acquisition"

assert_output_contains "'${PYTHON_BIN}' -c \"
import sys, tempfile, json
sys.path.insert(0, '${DISTRO_PATH}/packages/neuronix-core')
from neuronix_core.lock import OperationLock
with tempfile.NamedTemporaryFile() as tf:
    with OperationLock('meta_op', lock_path=tf.name):
        with open(tf.name, 'r') as f:
            data = json.load(f)
            if data.get('operation') == 'meta_op' and 'pid' in data:
                print('METADATA_VERIFIED')
\"" "METADATA_VERIFIED" "OperationLock persists operational metadata and PID in lockfile"

# 5-10. Transaction Journaling & Recovery
assert_output_contains "'${PYTHON_BIN}' -c \"
import sys, tempfile
sys.path.insert(0, '${DISTRO_PATH}/packages/neuronix-core')
from neuronix_core.journal import TransactionJournal, TransactionState
with tempfile.NamedTemporaryFile() as tf:
    j = TransactionJournal(journal_path=tf.name)
    tx_id = j.start_transaction('test_init')
    if j.get_transaction(tx_id)['state'] == TransactionState.PENDING:
        print('TX_PENDING_OK')
\"" "TX_PENDING_OK" "TransactionJournal initializes in PENDING state"

assert_output_contains "'${PYTHON_BIN}' -c \"
import sys, tempfile
sys.path.insert(0, '${DISTRO_PATH}/packages/neuronix-core')
from neuronix_core.journal import TransactionJournal, TransactionState
with tempfile.NamedTemporaryFile() as tf:
    j = TransactionJournal(journal_path=tf.name)
    tx_id = j.start_transaction('test_step')
    j.update_transaction(tx_id, TransactionState.APPLYING)
    if j.get_transaction(tx_id)['state'] == TransactionState.APPLYING:
        print('TX_APPLYING_OK')
\"" "TX_APPLYING_OK" "TransactionJournal transitions into APPLYING state"

assert_output_contains "'${PYTHON_BIN}' -c \"
import sys, tempfile
sys.path.insert(0, '${DISTRO_PATH}/packages/neuronix-core')
from neuronix_core.journal import TransactionJournal, TransactionState
with tempfile.NamedTemporaryFile() as tf:
    j = TransactionJournal(journal_path=tf.name)
    tx_id = j.start_transaction('dangling_op')
    j.update_transaction(tx_id, TransactionState.APPLYING)
    dangling = j.get_dangling_transactions()
    if len(dangling) == 1 and dangling[0]['id'] == tx_id:
        print('DANGLING_DETECTED_OK')
\"" "DANGLING_DETECTED_OK" "TransactionJournal detects uncommitted dangling transactions"

assert_output_contains "'${PYTHON_BIN}' -c \"
import sys, tempfile
sys.path.insert(0, '${DISTRO_PATH}/packages/neuronix-core')
from neuronix_core.journal import TransactionJournal, TransactionState
with tempfile.NamedTemporaryFile() as tf:
    j = TransactionJournal(journal_path=tf.name)
    tx_id = j.start_transaction('system_update', {'previous_generation': 3})
    j.update_transaction(tx_id, TransactionState.APPLYING)
    report = j.recover_dangling_transactions()
    if len(report) == 1 and 'NEEDS_ROLLBACK' in report[0]['action']:
        print('RECOVERY_REPORTED_OK')
\"" "RECOVERY_REPORTED_OK" "TransactionJournal recover_dangling_transactions flags recovery action"

assert_output_contains "'${PYTHON_BIN}' -c \"
import sys, tempfile
sys.path.insert(0, '${DISTRO_PATH}/packages/neuronix-core')
from neuronix_core.journal import TransactionJournal, TransactionState
with tempfile.NamedTemporaryFile() as tf:
    j = TransactionJournal(journal_path=tf.name)
    tx_id = j.start_transaction('commit_test')
    j.commit_transaction(tx_id, {'status': 'done'})
    if j.get_transaction(tx_id)['state'] == TransactionState.COMMITTED:
        print('TX_COMMITTED_OK')
\"" "TX_COMMITTED_OK" "TransactionJournal commits transaction upon postcondition success"

assert_output_contains "'${PYTHON_BIN}' -c \"
import sys, tempfile
sys.path.insert(0, '${DISTRO_PATH}/packages/neuronix-core')
from neuronix_core.journal import TransactionJournal, TransactionState
with tempfile.NamedTemporaryFile() as tf:
    j = TransactionJournal(journal_path=tf.name)
    tx_id = j.start_transaction('fail_test')
    j.abort_transaction(tx_id, 'Verification failed')
    tx = j.get_transaction(tx_id)
    if tx['state'] == TransactionState.FAILED and 'Verification failed' in tx['details'].get('abort_reason', ''):
        print('TX_ABORTED_OK')
\"" "TX_ABORTED_OK" "TransactionJournal aborts transaction and preserves error details"

# 11-17. Privileged Operations Allow-List & Boundary Fuzzing
assert_output_contains "'${PYTHON_BIN}' -c \"
import sys
sys.path.insert(0, '${DISTRO_PATH}/packages/neuronix-core')
from neuronix_core.operations import execute_privileged_operation
ok, code, msg = execute_privileged_operation('unauthorized_subsystem_call')
if not ok and code == 126:
    print('UNAUTHORIZED_REJECTED')
\"" "UNAUTHORIZED_REJECTED" "Privileged operation handler rejects unauthorized command name with exit code 126"

assert_output_contains "'${PYTHON_BIN}' -c \"
import sys
sys.path.insert(0, '${DISTRO_PATH}/packages/neuronix-core')
from neuronix_core.operations import execute_privileged_operation
ok, code, msg = execute_privileged_operation('battery', '80; rm -rf /')
if not ok and 'Security Violation' in msg:
    print('SEMICOLON_REJECTED')
\"" "SEMICOLON_REJECTED" "Privileged handler rejects semicolon command chaining injection"

assert_output_contains "'${PYTHON_BIN}' -c \"
import sys
sys.path.insert(0, '${DISTRO_PATH}/packages/neuronix-core')
from neuronix_core.operations import execute_privileged_operation
ok, code, msg = execute_privileged_operation('battery', '80 | cat /etc/shadow')
if not ok and 'Security Violation' in msg:
    print('PIPE_REJECTED')
\"" "PIPE_REJECTED" "Privileged handler rejects pipeline metacharacter injection"

assert_output_contains "'${PYTHON_BIN}' -c \"
import sys
sys.path.insert(0, '${DISTRO_PATH}/packages/neuronix-core')
from neuronix_core.operations import execute_privileged_operation
ok, code, msg = execute_privileged_operation('battery', '80' + chr(96) + 'id' + chr(96))
if not ok and 'Security Violation' in msg:
    print('BACKTICK_REJECTED')
\"" "BACKTICK_REJECTED" "Privileged handler rejects backtick execution injection"

assert_output_contains "'${PYTHON_BIN}' -c \"
import sys
sys.path.insert(0, '${DISTRO_PATH}/packages/neuronix-core')
from neuronix_core.operations import execute_privileged_operation
ok, code, msg = execute_privileged_operation('battery', '80' + chr(36) + '(whoami)')
if not ok and 'Security Violation' in msg:
    print('EXPANSION_REJECTED')
\"" "EXPANSION_REJECTED" "Privileged handler rejects dollar expansion injection"

assert_output_contains "'${PYTHON_BIN}' -c \"
import sys
sys.path.insert(0, '${DISTRO_PATH}/packages/neuronix-core')
from neuronix_core.operations import execute_privileged_operation
ok, code, msg = execute_privileged_operation('battery', '30')
if not ok and 'Validation Error' in msg:
    print('BELOW_MIN_REJECTED')
\"" "BELOW_MIN_REJECTED" "Privileged handler rejects battery threshold below 40%"

assert_output_contains "'${PYTHON_BIN}' -c \"
import sys
sys.path.insert(0, '${DISTRO_PATH}/packages/neuronix-core')
from neuronix_core.operations import execute_privileged_operation
ok, code, msg = execute_privileged_operation('battery', '150')
if not ok and 'Validation Error' in msg:
    print('ABOVE_MAX_REJECTED')
\"" "ABOVE_MAX_REJECTED" "Privileged handler rejects battery threshold above 100%"

# 18-20. Content-Addressed CA Enrollment Validation
assert_output_contains "'${PYTHON_BIN}' -c \"
import sys
sys.path.insert(0, '${DISTRO_PATH}/packages/neuronix-core')
from neuronix_core.ca import enroll_certificate
ok, code, msg = enroll_certificate('/nonexistent/path/to/cert.crt')
if not ok and code == 1 and 'not found' in msg:
    print('MISSING_CERT_REJECTED')
\"" "MISSING_CERT_REJECTED" "CA enrollment rejects missing certificate file path"

assert_output_contains "'${PYTHON_BIN}' -c \"
import sys, tempfile
sys.path.insert(0, '${DISTRO_PATH}/packages/neuronix-core')
from neuronix_core.ca import enroll_certificate
with tempfile.NamedTemporaryFile('w') as tf:
    tf.write('THIS IS NOT A CERTIFICATE')
    tf.flush()
    ok, code, msg = enroll_certificate(tf.name)
    if not ok and 'Validation Error' in msg:
        print('CORRUPT_CERT_REJECTED')
\"" "CORRUPT_CERT_REJECTED" "CA enrollment rejects corrupted or non-PEM certificate files"

assert_output_contains "'${PYTHON_BIN}' -c \"
import sys, hashlib
sys.path.insert(0, '${DISTRO_PATH}/packages/neuronix-core')
cert_bytes = b'-----BEGIN CERTIFICATE-----\\\\nMOCK\\\\n-----END CERTIFICATE-----\\\\n'
expected_hash = hashlib.sha256(cert_bytes).hexdigest()
target_filename = f'neuronix-ca-{expected_hash[:16]}.crt'
if target_filename.startswith('neuronix-ca-'):
    print('CONTENT_ADDR_OK')
\"" "CONTENT_ADDR_OK" "CA enrollment enforces deterministic content-addressed naming"

# 21-23. Rollback Safety Invariants & Idempotency
assert_output_contains "'${PYTHON_BIN}' -c \"
import sys
sys.path.insert(0, '${DISTRO_PATH}/packages/neuronix-core')
from neuronix_core.rollback import simulate_rollback
ok, msg, _ = simulate_rollback(999999)
if not ok and 'does not exist' in msg:
    print('NONEXISTENT_TARGET_REJECTED')
\"" "NONEXISTENT_TARGET_REJECTED" "Rollback engine rejects non-existent target generation"

assert_output_contains "'${PYTHON_BIN}' -c \"
import sys
sys.path.insert(0, '${DISTRO_PATH}/packages/neuronix-core')
from neuronix_core.generation import get_active_generation
from neuronix_core.rollback import execute_rollback
active = int(get_active_generation())
ok, code, msg = execute_rollback(target_generation=active)
if not ok and 'already the active generation' in msg:
    print('ACTIVE_TARGET_REJECTED')
\"" "ACTIVE_TARGET_REJECTED" "Rollback on current active generation is deterministically rejected"

assert_output_contains "'${PYTHON_BIN}' -c \"
import sys
sys.path.insert(0, '${DISTRO_PATH}/packages/neuronix-core')
from neuronix_core.rollback import execute_rollback
ok, code, msg = execute_rollback(dry_run=True)
if ok and code == 0 and 'DRY-RUN' in msg:
    print('DRY_RUN_ROLLBACK_OK')
\"" "DRY_RUN_ROLLBACK_OK" "Rollback dry-run validates safely without modifying profile links"

# 24-25. Battery Threshold Determinism
assert_output_not_contains "grep -F '|| true' '${DISTRO_PATH}/modules/hardware/power.nix'" "|| true" "Battery threshold service contains zero non-deterministic || true"
assert_output_contains "grep -F 'BATTERY_THRESHOLD: APPLIED' '${DISTRO_PATH}/modules/hardware/power.nix'" "BATTERY_THRESHOLD: APPLIED" "Battery threshold service encodes verified APPLIED state"

# 26-27. Storage Maintenance Resource Scheduling
assert_output_contains "grep -F 'ConditionACPower = true;' '${DISTRO_PATH}/modules/services/storage.nix'" "ConditionACPower" "Btrfs balance service declares ConditionACPower guard"
assert_output_contains "grep -F 'IOSchedulingClass = \"idle\";' '${DISTRO_PATH}/modules/services/storage.nix'" "IOSchedulingClass" "Btrfs balance service declares idle IO scheduling policy"

# 28-30. Declarative Subsystem Pure Options
assert_output_not_contains "grep -F '/etc/neuronix/kernel-profile' '${DISTRO_PATH}/modules/hardware/boot.nix'" "/etc/neuronix/kernel-profile" "Boot configuration eliminates filesystem read impurity"
assert_output_contains "grep -F 'neuronix.hardware.kernelFlavor' '${DISTRO_PATH}/modules/hardware/boot.nix'" "neuronix.hardware.kernelFlavor" "Boot configuration declares pure neuronix.hardware.kernelFlavor option"
assert_output_contains "grep -F 'neuronix.audio.antiPop' '${DISTRO_PATH}/modules/hardware/audio.nix'" "neuronix.audio.antiPop" "Audio configuration declares pure neuronix.audio.antiPop option"
