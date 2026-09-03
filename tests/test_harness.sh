#!/usr/bin/env bash
# ==============================================================================
# NEURONIX Industrial Test Harness Framework
# Provides strict assertion engines, TAP compatibility, and telemetry metrics.
# ==============================================================================

set -uo pipefail

export TOTAL_TESTS=0
export PASSED_TESTS=0
export FAILED_TESTS=0
export SUITE_NAME="GLOBAL"

# Color Codes
if [[ -t 1 ]]; then
    C_RESET="\033[0m"
    C_BOLD="\033[1m"
    C_GREEN="\033[32m"
    C_RED="\033[31m"
    C_CYAN="\033[36m"
    C_YELLOW="\033[33m"
    C_DIM="\033[2m"
else
    C_RESET=""
    C_BOLD=""
    C_GREEN=""
    C_RED=""
    C_CYAN=""
    C_YELLOW=""
    C_DIM=""
fi

start_suite() {
    SUITE_NAME="$1"
    echo -e "\n${C_BOLD}${C_CYAN}▶ [SUITE] ${SUITE_NAME}${C_RESET}"
}

record_pass() {
    local test_name="$1"
    ((TOTAL_TESTS++))
    ((PASSED_TESTS++))
    echo -e "  ${C_GREEN}✔ PASS${C_RESET} [${TOTAL_TESTS}] ${test_name}"
}

record_fail() {
    local test_name="$1"
    local reason="$2"
    ((TOTAL_TESTS++))
    ((FAILED_TESTS++))
    echo -e "  ${C_RED}✖ FAIL${C_RESET} [${TOTAL_TESTS}] ${test_name}"
    echo -e "         ${C_RED}Reason:${C_RESET} ${reason}"
}

assert_exit_code() {
    local cmd="$1"
    local expected="$2"
    local test_name="$3"

    local actual=0
    eval "$cmd" >/dev/null 2>&1 || actual=$?

    if [[ "$actual" -eq "$expected" ]]; then
        record_pass "${test_name} (exit: ${actual})"
    else
        record_fail "${test_name}" "Expected exit code ${expected}, but got ${actual}"
    fi
}

assert_output_contains() {
    local cmd="$1"
    local expected_str="$2"
    local test_name="$3"

    local output
    output="$(eval "$cmd" 2>&1)" || true

    if echo "$output" | grep -Fq -- "$expected_str"; then
        record_pass "${test_name}"
    else
        record_fail "${test_name}" "String '${expected_str}' was not found in output: '${output:0:150}...'"
    fi
}

assert_output_not_contains() {
    local cmd="$1"
    local forbidden_str="$2"
    local test_name="$3"

    local output
    output="$(eval "$cmd" 2>&1)" || true

    if ! echo "$output" | grep -Fq -- "$forbidden_str"; then
        record_pass "${test_name}"
    else
        record_fail "${test_name}" "Forbidden string '${forbidden_str}' was found in output."
    fi
}

assert_stderr_contains() {
    local cmd="$1"
    local expected_str="$2"
    local test_name="$3"

    local err_output
    err_output="$(eval "$cmd" 2>&1 >/dev/null)" || true

    if echo "$err_output" | grep -Fq -- "$expected_str"; then
        record_pass "${test_name} (in stderr)"
    else
        record_fail "${test_name}" "String '${expected_str}' was not present in stderr: '${err_output}'"
    fi
}

assert_eq() {
    local actual="$1"
    local expected="$2"
    local test_name="$3"

    if [[ "$actual" == "$expected" ]]; then
        record_pass "${test_name}"
    else
        record_fail "${test_name}" "Expected '${expected}', but got '${actual}'"
    fi
}
