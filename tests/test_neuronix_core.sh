#!/usr/bin/env bash
# ==============================================================================
# NEURONIX Automated Test Suite (Core Engine v0.1)
# ==============================================================================

set -uo pipefail

TARGET_BIN="/home/adamrofc/NEURONIX/bin/neuronix"

PASSED=0
FAILED=0

# Colors
GREEN="\033[32m"
RED="\033[31m"
CYAN="\033[36m"
BOLD="\033[1m"
RESET="\033[0m"

echo -e "\n${BOLD}${CYAN}======================================================${RESET}"
echo -e "${BOLD}${CYAN}   NEURONIX CORE ENGINE - AUTOMATED TEST SUITE        ${RESET}"
echo -e "${BOLD}${CYAN}======================================================${RESET}\n"

run_test() {
    local test_name="$1"
    local cmd="$2"
    local expected_code="$3"

    echo -ne "  [TEST] ${test_name} ... "

    local output
    local exit_code=0
    output="$(eval "$cmd" 2>&1)" || exit_code=$?

    if [[ "$exit_code" -eq "$expected_code" ]]; then
        echo -e "${GREEN}PASSED${RESET}"
        ((PASSED++))
    else
        echo -e "${RED}FAILED${RESET} (Expected exit code ${expected_code}, got ${exit_code})"
        echo -e "         Output:\n${output}\n"
        ((FAILED++))
    fi
}

assert_output_contains() {
    local test_name="$1"
    local cmd="$2"
    local expected_str="$3"

    echo -ne "  [TEST] ${test_name} ... "

    local output
    output="$(eval "$cmd" 2>&1)" || true

    if echo "$output" | grep -q "$expected_str"; then
        echo -e "${GREEN}PASSED${RESET}"
        ((PASSED++))
    else
        echo -e "${RED}FAILED${RESET} (Pattern '${expected_str}' not found in output)"
        echo -e "         Output:\n${output}\n"
        ((FAILED++))
    fi
}

# --- TEST CASES ---

# 1. Binary Permissions
run_test "Binary is executable" "test -x ${TARGET_BIN}" 0

# 2. Version and Help Flags
assert_output_contains "Command: version output" "${TARGET_BIN} version" "0.3.0-alpha"
assert_output_contains "Command: --version flag" "${TARGET_BIN} --version" "Apache License"
assert_output_contains "Command: help output" "${TARGET_BIN} help" "USAGE:"
assert_output_contains "Command: --help flag" "${TARGET_BIN} --help" "CORE COMMANDS:"

# 3. Invalid Command Handling
run_test "Invalid command exit code" "${TARGET_BIN} invalid_subcommand_xyz" 1
assert_output_contains "Invalid command error message" "${TARGET_BIN} invalid_subcommand_xyz" "tidak dikenali"

# 4. Status Command Verification
run_test "Command: status exit code" "${TARGET_BIN} status" 0
assert_output_contains "Status output: Kernel Telemetry" "${TARGET_BIN} status" "SYSTEM IDENTITY & KERNEL"
assert_output_contains "Status output: Storage Telemetry" "${TARGET_BIN} status" "STORAGE SUBSYSTEM TELEMETRY"
assert_output_contains "Status output: Systemd Timers" "${TARGET_BIN} status" "AUTONOMOUS TIMERS (SYSTEMD)"

# 5. Run Command Validation (Argument enforcement)
run_test "Run without args returns error" "${TARGET_BIN} run" 1
assert_output_contains "Run without args helpful tip" "${TARGET_BIN} run" "Silakan tentukan nama paket"

# 6. Ephemeral Execution Test (Pure environment without pollution)
assert_output_contains "Ephemeral run execution test" "nix-shell -p hello --run 'hello'" "Hello, world!"

echo -e "\n${BOLD}------------------------------------------------------${RESET}"
echo -e "Total Tests Passed : ${GREEN}${PASSED}${RESET}"
echo -e "Total Tests Failed : ${RED}${FAILED}${RESET}"
echo -e "${BOLD}------------------------------------------------------${RESET}\n"

if [[ "$FAILED" -eq 0 ]]; then
    echo -e "${GREEN}${BOLD}✔ ALL VERIFICATION TESTS PASSED WITH 100% CONFIDENCE!${RESET}\n"
    exit 0
else
    echo -e "${RED}${BOLD}✖ SOME TESTS FAILED. PLEASE AUDIT LOGS.${RESET}\n"
    exit 1
fi
