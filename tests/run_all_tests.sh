#!/usr/bin/env bash
# ==============================================================================
# NEURONIX Industrial QA & Resilience Master Test Runner (280+ Tests)
# Executes 13 deep-dive suites:
# 01 - Syntax & Static Analysis
# 02 - CLI Argument Parsing & Fuzzing
# 03 - Unit Tests for Internal Functions
# 04 - Storage Subsystem & Diet Resilience
# 05 - Ephemeral Sandbox & Isolation
# 06 - Fault Injection & Chaos Resilience
# 07 - Flake & Hermetic Reproducibility
# 08 - Environment Poisoning & Variable Sanitization
# 09 - Boundary, Buffer & Property-Based Fuzzing
# 10 - Filesystem Invariants & Symlink Defense
# 11 - Concurrency & Race Conditions
# 12 - Resource Exhaustion & POSIX ulimit Stress
# 13 - Mutation & Negative Invariants
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
echo -e "${C_BOLD}${C_CYAN}║     NEURONIX COMPREHENSIVE INDUSTRIAL QA & RESILIENCE HARNESS     ║${C_RESET}"
echo -e "${C_BOLD}${C_CYAN}║   Automated Mission-Critical Systems Verification (~506+ Tests)   ║${C_RESET}"
echo -e "${C_BOLD}${C_CYAN}╚═══════════════════════════════════════════════════════════════════╝${C_RESET}"

# Execute all 13 suites sequentially
source "$TEST_DIR/suites/01_syntax_and_static_analysis.sh"
source "$TEST_DIR/suites/02_cli_argument_and_fuzzing.sh"
source "$TEST_DIR/suites/03_unit_internal_functions.sh"
source "$TEST_DIR/suites/04_storage_and_diet_resilience.sh"
source "$TEST_DIR/suites/05_ephemeral_sandbox_isolation.sh"
source "$TEST_DIR/suites/06_fault_injection_and_chaos.sh"
source "$TEST_DIR/suites/07_flake_and_hermetic_reproducibility.sh"
source "$TEST_DIR/suites/08_env_poisoning_and_isolation.sh"
source "$TEST_DIR/suites/09_boundary_buffer_and_property_fuzzing.sh"
source "$TEST_DIR/suites/10_filesystem_invariants_and_symlink_defense.sh"
source "$TEST_DIR/suites/11_concurrency_race_conditions.sh"
source "$TEST_DIR/suites/12_resource_exhaustion_ulimit.sh"
source "$TEST_DIR/suites/13_mutation_and_negative_invariants.sh"
source "$TEST_DIR/suites/14_mcp_jsonrpc_protocol.sh"
source "$TEST_DIR/suites/15_shadow_vm_simulation.sh"
source "$TEST_DIR/suites/16_distro_standalone_architecture.sh"
source "$TEST_DIR/suites/17_distro_kernel_and_subsystem_invariants.sh"
source "$TEST_DIR/suites/18_distro_dev_stacks_and_fuzzing.sh"
source "$TEST_DIR/suites/19_distro_adr_and_architecture_contracts.sh"
source "$TEST_DIR/suites/20_distro_storage_and_btrfs_resilience.sh"
source "$TEST_DIR/suites/21_opencode_service_and_autoupdate.sh"

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

if [ "$FAILED_TESTS" -eq 0 ]; then
    echo -e "${C_GREEN}${C_BOLD}✓ NEURONIX VALIDATION SUITE PASSED: 100% OF DECLARED ASSERTIONS VERIFIED${C_RESET}"
    echo -e "${C_GREEN}   All subsystems, contracts, and failure modes verified against declared invariants.${C_RESET}\n"
    exit 0
else
    echo -e "${C_RED}${C_BOLD}❌ CERTIFICATION FAILED. REVIEW DETAILED LOGS ABOVE.${C_RESET}\n"
    exit 1
fi
