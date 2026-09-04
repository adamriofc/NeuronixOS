#!/usr/bin/env bash
# ==============================================================================
# NEURONIX System Manual & Native AI Reference Verification Gate
# Runs Suite 24 independently to ensure 100% compliance of documentation & AI models.
# ==============================================================================

set -uo pipefail
set +e
trap - PIPE

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${TEST_DIR}/.." && pwd)"
export PROJECT_ROOT
source "$TEST_DIR/test_harness.sh"

START_TIME=$(date +%s%N)

echo -e "\n${C_BOLD}${C_CYAN}╔═══════════════════════════════════════════════════════════════════╗${C_RESET}"
echo -e "${C_BOLD}${C_CYAN}║     NEURONIX SYSTEM-EMBEDDED MANUAL & AI REFERENCE GATE           ║${C_RESET}"
echo -e "${C_BOLD}${C_CYAN}║     Verifying Immutable Documentation & AI Directives (35 Tests)   ║${C_RESET}"
echo -e "${C_BOLD}${C_CYAN}╚═══════════════════════════════════════════════════════════════════╝${C_RESET}"

source "$TEST_DIR/suites/24_system_manual_and_ai_reference.sh"

END_TIME=$(date +%s%N)
DURATION_MS=$(( (END_TIME - START_TIME) / 1000000 ))

echo -e "\n${C_BOLD}═══════════════════════════════════════════════════════════════════${C_RESET}"
echo -e "${C_BOLD}                 SYSTEM MANUAL VERIFICATION SUMMARY                ${C_RESET}"
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

if [ "$FAILED_TESTS" -eq 0 ]; then
    echo -e "${C_GREEN}${C_BOLD}✓ SYSTEM MANUAL & AI REFERENCE PASSED: 100% COMPLIANT${C_RESET}\n"
    exit 0
else
    echo -e "${C_RED}${C_BOLD}✖ SYSTEM MANUAL VERIFICATION FAILED${C_RESET}\n"
    exit 1
fi
