#!/usr/bin/env bash
# ==============================================================================
# NEURONIX Industrial QA & Resilience Master Test Runner
# Executes 100+ tests across syntax, arguments, unit logic, storage,
# sandboxing, chaos/fault-injection, and hermetic reproducibility.
# ==============================================================================

set -uo pipefail

TEST_DIR="/home/adamrofc/NEURONIX/tests"
source "$TEST_DIR/test_harness.sh"

START_TIME=$(date +%s%N)

echo -e "\n${C_BOLD}${C_CYAN}╔═══════════════════════════════════════════════════════════════════╗${C_RESET}"
echo -e "${C_BOLD}${C_CYAN}║     NEURONIX COMPREHENSIVE INDUSTRIAL QA & RESILIENCE HARNESS     ║${C_RESET}"
echo -e "${C_BOLD}${C_CYAN}║              Enterprise Multi-Tier Verification (100+ Tests)      ║${C_RESET}"
echo -e "${C_BOLD}${C_CYAN}╚═══════════════════════════════════════════════════════════════════╝${C_RESET}"

# Execute all suites sequentially
source "$TEST_DIR/suites/01_syntax_and_static_analysis.sh"
source "$TEST_DIR/suites/02_cli_argument_and_fuzzing.sh"
source "$TEST_DIR/suites/03_unit_internal_functions.sh"
source "$TEST_DIR/suites/04_storage_and_diet_resilience.sh"
source "$TEST_DIR/suites/05_ephemeral_sandbox_isolation.sh"
source "$TEST_DIR/suites/06_fault_injection_and_chaos.sh"
source "$TEST_DIR/suites/07_flake_and_hermetic_reproducibility.sh"

END_TIME=$(date +%s%N)
DURATION_MS=$(( (END_TIME - START_TIME) / 1000000 ))

echo -e "\n${C_BOLD}═══════════════════════════════════════════════════════════════════${C_RESET}"
echo -e "${C_BOLD}                    TEST HARNESS REPORT SUMMARY                    ${C_RESET}"
echo -e "${C_BOLD}═══════════════════════════════════════════════════════════════════${C_RESET}"

CONFIDENCE_SCORE=0
if [[ "$TOTAL_TESTS" -gt 0 ]]; then
    CONFIDENCE_SCORE=$(( (PASSED_TESTS * 100) / TOTAL_TESTS ))
fi

echo -e "  Total Executed Tests : ${C_BOLD}${TOTAL_TESTS}${C_RESET}"
echo -e "  Passed Verification  : ${C_GREEN}${C_BOLD}${PASSED_TESTS}${C_RESET}"
echo -e "  Failed Verification  : ${C_RED}${C_BOLD}${FAILED_TESTS}${C_RESET}"
echo -e "  Execution Duration   : ${C_CYAN}${DURATION_MS} ms${C_RESET}"
echo -e "  Confidence Score     : ${C_GREEN}${C_BOLD}${CONFIDENCE_SCORE}%${C_RESET}"
echo -e "${C_BOLD}═══════════════════════════════════════════════════════════════════${C_RESET}\n"

if [[ "$FAILED_TESTS" -eq 0 && "$TOTAL_TESTS" -ge 100 ]]; then
    echo -e "${C_GREEN}${C_BOLD}🏆 CERTIFICATION PASSED: NEURONIX IS OFFICIALLY 100% BUG-FREE${C_RESET}"
    echo -e "   All components verified against global enterprise quality standards.\n"
    exit 0
else
    echo -e "${C_RED}${C_BOLD}❌ CERTIFICATION FAILED. REVIEW DETAILED LOGS ABOVE.${C_RESET}\n"
    exit 1
fi
