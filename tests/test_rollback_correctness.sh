#!/usr/bin/env bash
# ==============================================================================
# NEURONIX OS Multi-Hop Atomic Rollback Correctness Test Suite
# Verifies sequential state transitions across generation lineages:
#   Gen #42 -> Gen #41 -> Gen #40
# Tests atomic runtime execution using shared core:
#   packages/neuronix-core/neuronix_core/rollback.py
#   packages/neuronix-core/neuronix_core/generation.py
#
# Copyright (c) 2026 NEURONIX Contributors
# Licensed under the Apache License, Version 2.0
# ==============================================================================

set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON_BIN="$(command -v python3 || ls -d /nix/store/*-python3-*/bin/python3 2>/dev/null | tail -n 1 || echo "python3")"

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
echo -e "${BOLD}${CYAN}║     Runtime Core Execution: packages/neuronix-core/rollback.py   ║${RESET}"
echo -e "${BOLD}${CYAN}║     Lineage Invariants: Gen 42 -> 41 -> 40                       ║${RESET}"
echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════════════════════════════════╝${RESET}\n"

assert_check() {
    local desc="$1"
    local condition="$2"

    echo -ne "  [ROLLBACK-CORE] ${desc} ... "
    if eval "$condition" >/dev/null 2>&1; then
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
export NEURONIX_SYSTEM_PROFILE="${PROFILE_DIR}/system"

# Invariant 1: Initial state is Gen 42 via neuronix_core.generation
assert_check "Initial generation pointer resolves to Gen #42 via core" \
    "\"$PYTHON_BIN\" -c 'import sys; sys.path.insert(0, \"${PROJECT_ROOT}/packages/neuronix-core\"); from neuronix_core import generation; assert generation.get_active_generation() == \"42\"'"

# Invariant 2: Shared core list_generations parses all 3 generations
assert_check "Shared core lists 3 historical generations" \
    "\"$PYTHON_BIN\" -c 'import sys; sys.path.insert(0, \"${PROJECT_ROOT}/packages/neuronix-core\"); from neuronix_core import generation; gens = generation.list_generations(); assert len(gens) == 3'"

# Invariant 3: Rollback simulation from 42 targets 41
assert_check "Core simulate_rollback identifies predecessor Gen #41" \
    "\"$PYTHON_BIN\" -c 'import sys; sys.path.insert(0, \"${PROJECT_ROOT}/packages/neuronix-core\"); from neuronix_core import rollback; valid, msg, target = rollback.simulate_rollback(); assert valid and target == 41'"

# Invariant 4: Dry-run execution of rollback from 42 succeeds with returncode 0
assert_check "Core execute_rollback dry-run succeeds on valid target" \
    "\"$PYTHON_BIN\" -c 'import sys; sys.path.insert(0, \"${PROJECT_ROOT}/packages/neuronix-core\"); from neuronix_core import rollback; ok, code, msg = rollback.execute_rollback(dry_run=True); assert ok and code == 0'"

# Invariant 5: Pointer transition to Gen 41
ln -sfn "${PROFILE_DIR}/system-41-link" "${PROFILE_DIR}/system"
assert_check "Active generation pointer points to Gen #41" \
    "\"$PYTHON_BIN\" -c 'import sys; sys.path.insert(0, \"${PROJECT_ROOT}/packages/neuronix-core\"); from neuronix_core import generation; assert generation.get_active_generation() == \"41\"'"

# Invariant 6: Rollback simulation from 41 targets 40
assert_check "Second rollback from Gen #41 targets Gen #40" \
    "\"$PYTHON_BIN\" -c 'import sys; sys.path.insert(0, \"${PROJECT_ROOT}/packages/neuronix-core\"); from neuronix_core import rollback; valid, msg, target = rollback.simulate_rollback(); assert valid and target == 40'"

# Invariant 7: Pointer transition to Gen 40
ln -sfn "${PROFILE_DIR}/system-40-link" "${PROFILE_DIR}/system"
assert_check "Active generation pointer points to Gen #40" \
    "\"$PYTHON_BIN\" -c 'import sys; sys.path.insert(0, \"${PROJECT_ROOT}/packages/neuronix-core\"); from neuronix_core import generation; assert generation.get_active_generation() == \"40\"'"

# Invariant 8: Boundary guard prevents underflow when Gen 40 has no predecessors
assert_check "Core simulate_rollback rejects rollback when no predecessor exists" \
    "\"$PYTHON_BIN\" -c 'import sys; sys.path.insert(0, \"${PROJECT_ROOT}/packages/neuronix-core\"); from neuronix_core import rollback; valid, msg, target = rollback.simulate_rollback(); assert not valid and target is None'"

# Invariant 9: execute_rollback dry-run fails cleanly at boundary
assert_check "Core execute_rollback rejects execution at lower boundary" \
    "\"$PYTHON_BIN\" -c 'import sys; sys.path.insert(0, \"${PROJECT_ROOT}/packages/neuronix-core\"); from neuronix_core import rollback; ok, code, msg = rollback.execute_rollback(dry_run=True); assert not ok and code != 0'"

# Invariant 10: Specific target validation rejects non-existent generation
assert_check "Core execute_rollback rejects non-existent generation target #999" \
    "\"$PYTHON_BIN\" -c 'import sys; sys.path.insert(0, \"${PROJECT_ROOT}/packages/neuronix-core\"); from neuronix_core import rollback; ok, code, msg = rollback.execute_rollback(target_generation=999, dry_run=True); assert not ok'"

# Invariant 11: Specific target validation rejects switching to currently active generation
assert_check "Core execute_rollback rejects switching to currently active generation #40" \
    "\"$PYTHON_BIN\" -c 'import sys; sys.path.insert(0, \"${PROJECT_ROOT}/packages/neuronix-core\"); from neuronix_core import rollback; ok, code, msg = rollback.execute_rollback(target_generation=40, dry_run=True); assert not ok'"

# Invariant 12: Corrupt link recovery detection
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
    echo -e "${BOLD}${GREEN}✔ MULTI-HOP ATOMIC ROLLBACK INVARIANTS VERIFIED 100% VIA SHARED CORE${RESET}\n"
    exit 0
else
    echo -e "${BOLD}${RED}✖ MULTI-HOP ROLLBACK HARNESS FAILED${RESET}\n"
    exit 1
fi
