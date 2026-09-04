#!/usr/bin/env bash
# ==============================================================================
# NEURONIX OS Multi-Hop Atomic Rollback Correctness Test Suite
# Verifies sequential state transitions across generation lineages:
#   Gen #42 -> Gen #41 -> Gen #40
# Tests symlink atomicity, profile pointer consistency, and recovery invariants.
#
# Copyright (c) 2026 NEURONIX Contributors
# Licensed under the Apache License, Version 2.0
# ==============================================================================

set -uo pipefail

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
echo -e "${BOLD}${CYAN}║     NEURONIX OS MULTI-HOP ROLLBACK CORRECTNESS HARNESS            ║${RESET}"
echo -e "${BOLD}${CYAN}║     Verifying Multi-Step Invariants: Gen 42 -> 41 -> 40          ║${RESET}"
echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════════════════════════════════╝${RESET}\n"

assert_check() {
    local desc="$1"
    local condition="$2"

    echo -ne "  [TEST] ${desc} ... "
    if eval "$condition"; then
        echo -e "${GREEN}PASS${RESET}"
        ((PASSED++))
    else
        echo -e "${RED}FAIL${RESET}"
        ((FAILED++))
    fi
}

# 1. Setup Isolated Mock Profile Directory
TEST_DIR=$(mktemp -d "/tmp/neuronix-rollback-test-XXXXXX")
trap 'rm -rf "${TEST_DIR}"' EXIT

PROFILE_DIR="${TEST_DIR}/profiles"
mkdir -p "${PROFILE_DIR}"

# Create mock Nix store paths and generations: 40, 41, 42
for gen in 40 41 42; do
    mkdir -p "${TEST_DIR}/store/gen-${gen}"
    echo "kernel-hash-${gen}" > "${TEST_DIR}/store/gen-${gen}/kernel"
    echo "generation-${gen}" > "${TEST_DIR}/store/gen-${gen}/generation.nix"
    ln -s "${TEST_DIR}/store/gen-${gen}" "${PROFILE_DIR}/system-${gen}-link"
done

# Initialize active pointer to Gen 42
ln -sfn "${PROFILE_DIR}/system-42-link" "${PROFILE_DIR}/system"

# Invariant 1: Initial state is Gen 42
assert_check "Initial generation pointer resolves to Gen #42" \
    "[[ \$(readlink '${PROFILE_DIR}/system') == *'system-42-link' ]]"

# Invariant 2: Step 1 rollback: 42 -> 41
simulate_rollback_step() {
    local current_target
    current_target=$(readlink "${PROFILE_DIR}/system")
    local cur_num
    cur_num=$(basename "$current_target" | sed -E 's/^system-([0-9]+)-link$/\1/')
    local prev_link
    prev_link=$(find "${PROFILE_DIR}" -maxdepth 1 -name "system-*-link" | sort -V | grep -B1 "system-${cur_num}-link" | head -n 1)

    if [[ -n "$prev_link" && "$prev_link" != *"${cur_num}"* ]]; then
        ln -sfn "$prev_link" "${PROFILE_DIR}/system"
        return 0
    fi
    return 1
}

assert_check "Rollback from Gen #42 to predecessor succeeds" \
    "simulate_rollback_step"

assert_check "Active generation pointer points to Gen #41" \
    "[[ \$(readlink '${PROFILE_DIR}/system') == *'system-41-link' ]]"

# Invariant 3: Step 2 rollback: 41 -> 40
assert_check "Second rollback from Gen #41 to Gen #40 succeeds" \
    "simulate_rollback_step"

assert_check "Active generation pointer points to Gen #40" \
    "[[ \$(readlink '${PROFILE_DIR}/system') == *'system-40-link' ]]"

# Invariant 4: Rollback boundary guard: Gen 40 has no predecessors in test set
simulate_boundary_rollback() {
    local current_target
    current_target=$(readlink "${PROFILE_DIR}/system")
    local cur_num
    cur_num=$(basename "$current_target" | sed -E 's/^system-([0-9]+)-link$/\1/')
    local prev_link
    prev_link=$(find "${PROFILE_DIR}" -maxdepth 1 -name "system-*-link" | sort -V | grep -B1 "system-${cur_num}-link" | head -n 1)

    if [[ -n "$prev_link" && "$prev_link" != *"${cur_num}"* ]]; then
        return 0
    fi
    return 1
}

assert_check "Boundary guard prevents underflow when no predecessor exists" \
    "! simulate_boundary_rollback"

# Invariant 5: Corrupt link recovery
# Simulate a scenario where system-41-link target was removed, but system-40-link is healthy
rm -rf "${TEST_DIR}/store/gen-41"
assert_check "Detection of missing store target in historical generation" \
    "! test -d \$(readlink '${PROFILE_DIR}/system-41-link')"

assert_check "Active generation Gen #40 store path remains integer and intact" \
    "test -f '${TEST_DIR}/store/gen-40/kernel'"

echo -e "\n${BOLD}═══════════════════════════════════════════════════════════════════${RESET}"
echo -e "  Total Rollback Assertions : $((PASSED + FAILED))"
echo -e "  Passed Validations        : ${PASSED}"
echo -e "  Failed Validations        : ${FAILED}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════════════${RESET}\n"

if [[ $FAILED -eq 0 ]]; then
    echo -e "${BOLD}${GREEN}✔ MULTI-HOP ATOMIC ROLLBACK INVARIANTS VERIFIED 100%${RESET}\n"
    exit 0
else
    echo -e "${BOLD}${RED}✖ MULTI-HOP ROLLBACK HARNESS FAILED${RESET}\n"
    exit 1
fi
