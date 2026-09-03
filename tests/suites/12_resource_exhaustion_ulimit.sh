#!/usr/bin/env bash
# Suite 12: Resource Exhaustion & POSIX ulimit Stress Testing (20 Tests)

TARGET_BIN="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/bin/neuronix"

start_suite "12 - Resource Exhaustion & POSIX ulimit Stress"

# 1-5. File Descriptor Limit Throttling (ulimit -n)
assert_exit_code "(ulimit -n 1024 && $TARGET_BIN version)" 0 "ulimit -n 1024 executes version with exit 0"
assert_exit_code "(ulimit -n 512 && $TARGET_BIN help)" 0 "ulimit -n 512 executes help with exit 0"
assert_exit_code "(ulimit -n 256 && $TARGET_BIN version)" 0 "ulimit -n 256 executes version with exit 0"
assert_exit_code "(ulimit -n 128 && $TARGET_BIN help)" 0 "ulimit -n 128 executes help with exit 0"
assert_output_contains "(ulimit -n 256 && $TARGET_BIN version)" "0.3.0-alpha" "Low fd limit preserves output integrity"

# 6-10. Core Dump Prevention (ulimit -c 0)
assert_exit_code "(ulimit -c 0 && $TARGET_BIN version)" 0 "ulimit -c 0 executes version with exit 0"
assert_exit_code "(ulimit -c 0 && $TARGET_BIN status)" 0 "ulimit -c 0 executes status with exit 0"
assert_exit_code "(ulimit -c 0 && $TARGET_BIN invalid_cmd_xyz)" 1 "ulimit -c 0 safely exits 1 on invalid command without core dumping"
assert_eq "$(ls -1 /tmp/core* 2>/dev/null | wc -l)" "0" "Zero core dump files generated in /tmp"
assert_output_contains "(ulimit -c 0 && $TARGET_BIN version)" "Apache License" "Core dump suppression preserves version text"

# 11-15. Memory / Stack Size Constraints
assert_exit_code "(ulimit -s 8192 && $TARGET_BIN version)" 0 "Standard 8MB stack executes version with exit 0"
assert_exit_code "(ulimit -s 4096 && $TARGET_BIN help)" 0 "Throttled 4MB stack executes help with exit 0"
assert_exit_code "(ulimit -s 2048 && $TARGET_BIN version)" 0 "Throttled 2MB stack executes version with exit 0"
assert_output_contains "(ulimit -s 4096 && $TARGET_BIN version)" "Substrate" "Throttled stack output matches expectation"
assert_output_contains "(ulimit -s 2048 && $TARGET_BIN help)" "CORE COMMANDS:" "Throttled stack help matches expectation"

# 16-20. Pipe Capacity & Buffering Stress
assert_exit_code "$TARGET_BIN version | head -n 1" 0 "Piping to 'head -n 1' exits with clean pipe closing"
assert_exit_code "$TARGET_BIN help | head -n 5" 0 "Piping to 'head -n 5' handles early SIGPIPE cleanly"
assert_exit_code "$TARGET_BIN status | wc -l >/dev/null" 0 "Piping to 'wc -l' executes without hanging"
assert_exit_code "$TARGET_BIN version | tr '[:lower:]' '[:upper:]' | grep -q 'NEURONIX'" 0 "Multi-stage POSIX pipeline executes cleanly"
assert_output_contains "$TARGET_BIN version | tr '[:lower:]' '[:upper:]'" "APACHE LICENSE" "Pipeline transformation preserves text semantics"
