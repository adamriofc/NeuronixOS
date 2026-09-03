#!/usr/bin/env bash
# Suite 05: Ephemeral Sandbox & Isolation (15 Tests)

start_suite "05 - Ephemeral Sandbox & Isolation"

# 1. Verification of nix-shell availability
assert_eq "$(command -v nix-shell >/dev/null && echo "found" || echo "missing")" "found" "nix-shell binary is available"

# 2. Ephemeral single-command execution
assert_output_contains "nix-shell -p hello --run 'hello'" "Hello, world!" "nix-shell executes 'hello' binary"
assert_exit_code "nix-shell -p hello --run 'hello'" 0 "nix-shell with valid command exits 0"

# 3. Exit Code Propagation: Exit 0
assert_exit_code "nix-shell -p coreutils --run 'exit 0'" 0 "Exit code 0 is propagated accurately"

# 4. Exit Code Propagation: Exit 42
assert_exit_code "nix-shell -p coreutils --run 'exit 42'" 42 "Exit code 42 is propagated accurately"

# 5. Exit Code Propagation: Exit 127 (Command not found)
assert_exit_code "nix-shell -p coreutils --run 'nonexistent_cmd_xyz'" 127 "Exit code 127 is propagated for command not found"

# 6. Multi-package ephemeral workspace
assert_output_contains "nix-shell -p which hello --run 'which hello'" "/bin/hello" "Multiple packages (which + hello) co-exist in subshell"

# 7. Environment variable isolation (No leakage to parent)
TEST_VAR_LEAK="UNSET"
nix-shell -p coreutils --run 'export TEST_VAR_LEAK="LEAKED"' >/dev/null 2>&1 || true
assert_eq "$TEST_VAR_LEAK" "UNSET" "Child subshell environment variables do NOT leak into parent shell"

# 8. Working Directory Preservation
CURRENT_DIR="$PWD"
SUBSHELL_DIR="$(nix-shell -p coreutils --run 'pwd')"
assert_eq "$SUBSHELL_DIR" "$CURRENT_DIR" "Subshell inherits and preserves current working directory ($CURRENT_DIR)"

# 9. Clean Temp Directory Isolation
TMP_BEFORE_COUNT="$(ls -1 /tmp | wc -l)"
nix-shell -p hello --run 'hello' >/dev/null 2>&1
TMP_AFTER_COUNT="$(ls -1 /tmp | wc -l)"
assert_eq "$TMP_BEFORE_COUNT" "$TMP_AFTER_COUNT" "Zero temporary files leaked into /tmp during ephemeral run"

# 10. Read-only /nix/store enforcement in subshell
assert_exit_code "nix-shell -p coreutils --run 'touch /nix/store/test_file_leak 2>/dev/null'" 1 "Store remains read-only; touch fails inside subshell"
