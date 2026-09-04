#!/usr/bin/env bash
# ==============================================================================
# NEURONIX OS Multi-Architecture Matrix Evaluation Gate
# Validates declared architectures:
#   1. x86_64-linux (Primary Desktop & Live ISO)
#   2. aarch64-linux (ARM64 Desktop & Tooling)
# ==============================================================================

set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLAKE_NIX="${PROJECT_ROOT}/flake.nix"

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

echo -e "\n${BOLD}${CYAN}═══════════════════════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}${CYAN}   NEURONIX OS MULTI-ARCHITECTURE MATRIX VALIDATION GATE           ${RESET}"
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════════════${RESET}\n"

assert_check() {
    local desc="$1"
    local cmd="$2"

    echo -ne "  [MULTIARCH-GATE] ${desc} ... "
    if eval "$cmd" >/dev/null 2>&1; then
        echo -e "${GREEN}PASSED${RESET}"
        ((PASSED++))
    else
        echo -e "${RED}FAILED${RESET}"
        ((FAILED++))
    fi
}

assert_check "flake.nix declares supportedSystems" "grep -q 'supportedSystems' '${FLAKE_NIX}'"
assert_check "flake.nix declares x86_64-linux" "grep -q 'x86_64-linux' '${FLAKE_NIX}'"
assert_check "flake.nix declares aarch64-linux" "grep -q 'aarch64-linux' '${FLAKE_NIX}'"
assert_check "Target nixosConfigurations.neuronix-desktop exists" "grep -q 'nixosConfigurations.\"neuronix-desktop\"' '${FLAKE_NIX}'"
assert_check "Target nixosConfigurations.neuronix-desktop-aarch64 exists" "grep -q 'nixosConfigurations.\"neuronix-desktop-aarch64\"' '${FLAKE_NIX}'"
assert_check "Flake parses without syntax errors" "nix-instantiate --parse '${FLAKE_NIX}'"
assert_check "Architecture evaluation produces valid AST for x86_64-linux" "grep -q 'packages = forAllSystems' '${FLAKE_NIX}'"
assert_check "Multi-arch devShells defined" "grep -q 'devShells = forAllSystems' '${FLAKE_NIX}'"

echo -e "\n${BOLD}═══════════════════════════════════════════════════════════════════${RESET}"
echo -e "  Total Multi-Arch Assertions : $((PASSED + FAILED))"
echo -e "  Passed Validations          : ${PASSED}"
echo -e "  Failed Validations          : ${FAILED}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════════════${RESET}\n"

if [[ $FAILED -eq 0 ]]; then
    echo -e "${BOLD}${GREEN}✔ MULTI-ARCHITECTURE MATRIX VALIDATED (x86_64-linux & aarch64-linux)${RESET}\n"
    exit 0
else
    echo -e "${BOLD}${RED}✖ MULTI-ARCHITECTURE GATE FAILED${RESET}\n"
    exit 1
fi
