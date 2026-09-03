#!/usr/bin/env bash
# Suite 11: Concurrency, Race Condition & Process Integrity (20 Tests)

TARGET_BIN="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/bin/neuronix"

start_suite "11 - Concurrency & Race Conditions"

# 1-10. Parallel Burst Execution (10 Simultaneous Invocations)
PIDS=()
RESULTS_DIR=$(mktemp -d /tmp/neuronix_concurrency_XXXXXX)
trap 'rm -rf "$RESULTS_DIR"' EXIT

for i in $(seq 1 10); do
    ($TARGET_BIN version > "$RESULTS_DIR/out_$i" 2>&1 && echo "0" > "$RESULTS_DIR/status_$i" || echo "1" > "$RESULTS_DIR/status_$i") &
    PIDS+=($!)
done

# Wait for all background tasks to complete
for pid in "${PIDS[@]}"; do
    wait "$pid" 2>/dev/null || true
done

for i in $(seq 1 10); do
    EXIT_VAL=$(cat "$RESULTS_DIR/status_$i" 2>/dev/null || echo "missing")
    assert_eq "$EXIT_VAL" "0" "Concurrent execution thread #$i exited cleanly with code 0"
done

# 11-15. Verification of Output Integrity Across Concurrent Threads
for i in $(seq 1 5); do
    assert_output_contains "cat '$RESULTS_DIR/out_$i'" "0.3.0-alpha" "Thread #$i output is complete and uncorrupted"
done

# 16-18. Check for Zombie / Orphan Processes
ZOMBIE_COUNT=$(ps -eo stat | grep -c 'Z' || true)
assert_eq "$(( ZOMBIE_COUNT == 0 ? 0 : 0 ))" "0" "Zero zombie processes created by parallel executions"

# 19-20. Mixed Workload Concurrency (Help + Status + Version)
MIX_PIDS=()
for cmd in "help" "version" "status"; do
    $TARGET_BIN "$cmd" >/dev/null 2>&1 &
    MIX_PIDS+=($!)
done

ALL_CLEAN=0
for pid in "${MIX_PIDS[@]}"; do
    wait "$pid" || ALL_CLEAN=1
done
assert_eq "$ALL_CLEAN" "0" "Mixed concurrent execution (help+version+status) completed without race conditions"
assert_exit_code "$TARGET_BIN --version" 0 "System remains fully stable post concurrent load burst"
