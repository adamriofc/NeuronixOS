#!/usr/bin/env bash
# Suite 02: CLI Argument Dispatcher and Fuzzing (25 Tests)

TARGET_BIN="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/bin/neuronix"

start_suite "02 - CLI Argument Parsing & Fuzzing"

# 1. No arguments should display help and exit 0
assert_exit_code "$TARGET_BIN" 0 "Empty invocation exits 0"
assert_output_contains "$TARGET_BIN" "USAGE:" "Empty invocation shows USAGE"

# 2. Flag: help
assert_exit_code "$TARGET_BIN help" 0 "Command 'help' exits 0"
assert_output_contains "$TARGET_BIN help" "CORE COMMANDS:" "Command 'help' shows commands"

# 3. Flag: -h
assert_exit_code "$TARGET_BIN -h" 0 "Flag '-h' exits 0"
assert_output_contains "$TARGET_BIN -h" "USAGE:" "Flag '-h' shows USAGE"

# 4. Flag: --help
assert_exit_code "$TARGET_BIN --help" 0 "Flag '--help' exits 0"
assert_output_contains "$TARGET_BIN --help" "EXAMPLES:" "Flag '--help' shows EXAMPLES"

# 5. Flag: version
assert_exit_code "$TARGET_BIN version" 0 "Command 'version' exits 0"
assert_output_contains "$TARGET_BIN version" "$CANONICAL_VERSION" "Command 'version' contains version string"

# 6. Flag: -v
assert_exit_code "$TARGET_BIN -v" 0 "Flag '-v' exits 0"
assert_output_contains "$TARGET_BIN -v" "$CANONICAL_VERSION" "Flag '-v' contains version string"

# 7. Flag: --version
assert_exit_code "$TARGET_BIN --version" 0 "Flag '--version' exits 0"
assert_output_contains "$TARGET_BIN --version" "Apache License 2.0" "Flag '--version' contains license"

# 8. Invalid commands
assert_exit_code "$TARGET_BIN foobar_command" 1 "Unknown command exits 1"
assert_output_contains "$TARGET_BIN foobar_command" "tidak dikenali" "Unknown command triggers error message"

# 9. Stderr separation: error message must be on stderr
assert_stderr_contains "$TARGET_BIN non_existent_cmd" "tidak dikenali" "Error message sent to stderr"

# 10. Whitespace argument fuzzing
assert_exit_code "$TARGET_BIN '   '" 1 "All-whitespace command exits 1"

# 11. Hyphen fuzzing
assert_exit_code "$TARGET_BIN --unknown-flag" 1 "Unknown flag '--unknown-flag' exits 1"
assert_exit_code "$TARGET_BIN -z" 1 "Unknown short flag '-z' exits 1"

# 12. Special characters fuzzing
assert_exit_code "$TARGET_BIN '!@#\$%^&*()'" 1 "Special characters command exits 1"
assert_exit_code "$TARGET_BIN '../../etc/passwd'" 1 "Path traversal injection command exits 1"
assert_exit_code "$TARGET_BIN '<script>alert(1)</script>'" 1 "XSS style command exits 1"
assert_exit_code "$TARGET_BIN ';; rm -rf /'" 1 "Command injection string exits 1"

# 13. Case sensitivity
assert_exit_code "$TARGET_BIN STATUS" 1 "Uppercase command 'STATUS' is rejected cleanly with exit 1"
assert_exit_code "$TARGET_BIN Diet" 1 "Capitalized command 'Diet' is rejected cleanly with exit 1"

# 14. Unicode fuzzing
assert_exit_code "$TARGET_BIN '🔥🚀' " 1 "Emoji command exits 1"
assert_exit_code "$TARGET_BIN '日本語' " 1 "CJK unicode command exits 1"
assert_exit_code "$TARGET_BIN 'тест' " 1 "Cyrillic unicode command exits 1"

# 15. Subcommand argument enforcement
assert_exit_code "$TARGET_BIN run" 1 "Subcommand 'run' without package exits 1"
assert_stderr_contains "$TARGET_BIN run" "Silakan tentukan nama paket" "Subcommand 'run' without package warns user"

# 16. Verification argument sanitization and injection rejection
assert_exit_code "$TARGET_BIN verify 'hello;whoami'" 1 "Subcommand 'verify' rejects semicolon injection with exit 1"
assert_stderr_contains "$TARGET_BIN verify 'hello;whoami'" "Must match regex" "Subcommand 'verify' emits regex error on invalid package"
assert_exit_code "$TARGET_BIN verify 'hello\"abort'" 1 "Subcommand 'verify' rejects quote injection with exit 1"
