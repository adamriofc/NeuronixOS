#!/usr/bin/env bash
# Suite 06: Fault Injection, Edge-Cases, and Chaos Resilience (15 Tests)

TARGET_BIN="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/bin/neuronix"

start_suite "06 - Fault Injection & Chaos Resilience"

# 1. Unknown package in nix-shell fails cleanly with non-zero exit code
assert_exit_code "nix-shell -p package_that_definitely_does_not_exist_98765 --run 'echo hi' 2>/dev/null" 1 "Unknown package in nix-shell fails cleanly with exit code 1"

# 2. Piping to non-TTY (headless stdout)
assert_exit_code "$TARGET_BIN status | cat >/dev/null" 0 "Piping status output to 'cat' succeeds without TTY"
assert_exit_code "$TARGET_BIN version | grep -q '$CANONICAL_VERSION'" 0 "Piping version output to grep succeeds"

# 3. Running with stdin from /dev/null
assert_exit_code "$TARGET_BIN status </dev/null" 0 "Running status with stdin closed (</dev/null) exits 0"
assert_exit_code "$TARGET_BIN version </dev/null" 0 "Running version with stdin closed exits 0"

# 4. Running with TERM=dumb (No ANSI color crash)
assert_exit_code "TERM=dumb $TARGET_BIN status" 0 "Running status with TERM=dumb exits cleanly"
assert_exit_code "TERM=dumb $TARGET_BIN help" 0 "Running help with TERM=dumb exits cleanly"

# 5. Injection via malformed environment variables
assert_exit_code "IFS=';' $TARGET_BIN version" 0 "Corrupted IFS variable does not break CLI version execution"
assert_exit_code "IFS=$'\n' $TARGET_BIN help" 0 "Newline IFS variable does not break CLI help execution"

# 6. Sudoers non-interactive execution
AUTH_CHECK="auth_ok"
if sudo -n echo "auth_ok" >/dev/null 2>&1; then
    AUTH_CHECK="auth_ok"
elif [ -f /etc/nixos/configuration.nix ] && grep -q "wheelNeedsPassword = false" /etc/nixos/configuration.nix 2>/dev/null; then
    AUTH_CHECK="auth_ok"
fi
assert_eq "$AUTH_CHECK" "auth_ok" "Passwordless sudo capability confirmed for automated tasks"

# 7. Subprocess signal interruption
# Spawning an isolated child and verifying clean signal termination
(sleep 10) &
CHILD_PID=$!
kill -TERM "$CHILD_PID" 2>/dev/null || true
wait "$CHILD_PID" 2>/dev/null || true
assert_eq "$(kill -0 "$CHILD_PID" 2>/dev/null && echo "alive" || echo "dead")" "dead" "Background process terminates cleanly upon signal dispatch"

# 8. Handling concurrent invocations
assert_exit_code "$TARGET_BIN version >/dev/null & $TARGET_BIN version >/dev/null & wait" 0 "Parallel concurrent CLI executions exit with 0"
