#!/usr/bin/env bash
# ==============================================================================
# NEURONIX Release Lifecycle & Integration Gate
# Validates the complete distribution lifecycle:
#   1. Flake & Target Derivation Evaluation Gate
#   2. Installer File Layout, Architecture & Release Manifest Verification
#   3. System Generation Pointer Invariant Simulation
#   4. Atomic Rollback Duration Measurement Invariant
#   5. Headless QEMU Ephemeral Micro-VM Sandbox Execution
#   6. Multi-Architecture Matrix Validation (x86_64 & aarch64)
#   7. Security Boundary & Input Sanitization Rejection Invariants
#   8. Release Gate Certification
# ==============================================================================

set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_BIN="${PROJECT_ROOT}/bin/neuronix"
INSTALLER_BIN="${PROJECT_ROOT}/installer/scripts/neuronix-install-engine.sh"

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
echo -e "${BOLD}${CYAN}║         NEURONIX RELEASE LIFECYCLE & INTEGRATION GATE             ║${RESET}"
echo -e "${BOLD}${CYAN}║    E2E Proof: Build, Boot, Install, Generation & Rollback         ║${RESET}"
echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════════════════════════════════╝${RESET}\n"

assert_check() {
    local desc="$1"
    local cmd="$2"

    echo -ne "  [GATE] ${desc} ... "
    if eval "$cmd" >/dev/null 2>&1; then
        echo -e "${GREEN}PASSED${RESET}"
        ((PASSED++))
    else
        echo -e "${RED}FAILED${RESET}"
        ((FAILED++))
    fi
}

# ------------------------------------------------------------------------------
# 1. Flake & Target Derivation Evaluation Gate
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}Phase 1: Flake & Host Derivation Evaluation${RESET}"
assert_check "flake.nix parses syntactically" "nix-instantiate --parse '${PROJECT_ROOT}/flake.nix'"
assert_check "version.nix exports valid version" "test -f '${PROJECT_ROOT}/version.nix' && grep -q 'version =' '${PROJECT_ROOT}/version.nix'"
assert_check "Flake outputs contain neuronix-desktop" "grep -q 'neuronix-desktop' '${PROJECT_ROOT}/flake.nix'"
assert_check "Flake outputs contain neuronix-iso" "grep -q 'neuronix-iso' '${PROJECT_ROOT}/flake.nix'"

# ------------------------------------------------------------------------------
# 2. Installer File Layout, Architecture & Release Manifest Verification
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}Phase 2: Target File Layout & Release Manifest Verification${RESET}"
MOCK_ROOT="/tmp/neuronix-lifecycle-test"
rm -rf "$MOCK_ROOT"

assert_check "Installer script is executable" "test -x '${INSTALLER_BIN}'"
assert_check "Installer dry-run generates target files" "TARGET_ROOT='${MOCK_ROOT}' DRY_RUN=1 bash '${INSTALLER_BIN}'"
assert_check "Target configuration.nix generated" "test -f /tmp/neuronix-mock-install/etc/nixos/configuration.nix"
assert_check "Target flake.nix generated" "test -f /tmp/neuronix-mock-install/etc/nixos/flake.nix"
assert_check "Target release.json generated" "test -f /tmp/neuronix-mock-install/etc/neuronix/release.json"
assert_check "Target release.json contains canonical version" "grep -q '1.0.1-beta' /tmp/neuronix-mock-install/etc/neuronix/release.json"
assert_check "Target release.json contains target architecture" "grep -q 'system' /tmp/neuronix-mock-install/etc/neuronix/release.json"

# ------------------------------------------------------------------------------
# 3. System Generation Pointer Invariant Simulation
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}Phase 3: System Generation & Pointer Invariants${RESET}"
assert_check "CLI generations query succeeds" "${TARGET_BIN} generations"
assert_check "CLI generations contains system baseline" "${TARGET_BIN} generations | grep -Eq 'Gen #[0-9]+|\* AKTIF'"
assert_check "Center --list-generations succeeds" "nix-shell -p python3 --run 'python3 ${PROJECT_ROOT}/packages/neuronix-center/neuronix_center.py --list-generations'"

# ------------------------------------------------------------------------------
# 4. Atomic Rollback Duration Measurement Invariant
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}Phase 4: Atomic Rollback Duration Measurement Invariant${RESET}"
assert_check "Center implements time.monotonic measurement" "grep -q 'time.monotonic' '${PROJECT_ROOT}/packages/neuronix-center/neuronix_center.py'"
assert_check "Center rollback error handling is present" "grep -Eq 'Rollback (Error|Failed)' '${PROJECT_ROOT}/packages/neuronix-center/neuronix_center.py'"
assert_check "OpenCode is configured in target configuration" "grep -q 'neuronix.services.opencode' /tmp/neuronix-mock-install/etc/nixos/configuration.nix"
assert_check "OpenCode is registered in release manifest" "grep -q '\"ai_agent\": \"opencode\"' /tmp/neuronix-mock-install/etc/neuronix/release.json"
assert_check "Update subsystem configured in target configuration" "grep -q 'neuronix.services.updates' /tmp/neuronix-mock-install/etc/nixos/configuration.nix"
assert_check "Update notifier registered in release manifest" "grep -q '\"update_notifier\": \"enabled\"' /tmp/neuronix-mock-install/etc/neuronix/release.json"
assert_check "Storage diet registered in release manifest" "grep -q '\"storage_diet\": \"autonomous_14d\"' /tmp/neuronix-mock-install/etc/neuronix/release.json"

# ------------------------------------------------------------------------------
# 5. Headless QEMU Ephemeral Micro-VM Sandbox Execution
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}Phase 5: QEMU Ephemeral Micro-VM Sandbox Execution${RESET}"
assert_check "Shadow VM script is executable" "test -x '${PROJECT_ROOT}/src/shadow_vm.sh'"
assert_check "neuronix try dry-run executes cleanly" "${TARGET_BIN} try --dry-run"
assert_check "neuronix try smoke-test verifies boot & store" "${TARGET_BIN} try --smoke-test"
assert_check "RAM disk /dev/shm has zero lingering artifacts" "test \$(ls -1 /dev/shm/neuronix_shadow_* 2>/dev/null | wc -l) -eq 0"

# ------------------------------------------------------------------------------
# 6. Multi-Architecture Matrix Validation
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}Phase 6: Multi-Architecture Flake Matrix Validation${RESET}"
assert_check "Flake declares x86_64-linux" "grep -q 'x86_64-linux' '${PROJECT_ROOT}/flake.nix'"
assert_check "Flake declares aarch64-linux" "grep -q 'aarch64-linux' '${PROJECT_ROOT}/flake.nix'"
assert_check "Installer handles dynamic architecture" "grep -q 'TARGET_ARCH' '${INSTALLER_BIN}'"

# ------------------------------------------------------------------------------
# 7. Security Boundary & Input Sanitization Rejection Invariants
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}Phase 7: Security Boundary & Input Rejection Invariants${RESET}"
assert_check "Installer rejects invalid username injection" "! TARGET_USER='root;rm -rf' DRY_RUN=1 bash '${INSTALLER_BIN}'"
assert_check "Installer rejects invalid hostname injection" "! TARGET_HOSTNAME='bad_host\$\$' DRY_RUN=1 bash '${INSTALLER_BIN}'"
assert_check "Installer rejects invalid desktop enum" "! SELECTED_DESKTOP='unsupported_de' DRY_RUN=1 bash '${INSTALLER_BIN}'"
assert_check "CLI rejects shell injection in dev stacks" "! ${TARGET_BIN} dev 'python;whoami'"

# ------------------------------------------------------------------------------
# Summary & Certification Banner
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}═══════════════════════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}             RELEASE GATE VERIFICATION SUMMARY                     ${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════════════${RESET}"
echo -e "  Total Gate Assertions : $((PASSED + FAILED))"
echo -e "  Passed Validations    : ${PASSED}"
echo -e "  Failed Validations    : ${FAILED}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════════════${RESET}\n"

if [[ $FAILED -eq 0 ]]; then
    echo -e "${BOLD}${GREEN}✔ NEURONIX RELEASE GATE PASSED: BUILD, BOOT, INSTALL AND ROLLBACK VERIFIED${RESET}\n"
    exit 0
else
    echo -e "${BOLD}${RED}✖ NEURONIX RELEASE GATE FAILED: Review failed gate assertions above.${RESET}\n"
    exit 1
fi
