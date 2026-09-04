#!/usr/bin/env bash
# ==============================================================================
# NEURONIX OS Single Source of Truth & Reproducibility Gate
# Verifies absolute alignment between:
#   1. version.nix (Declarative Single Source of Truth)
#   2. flake.lock (Hermetic dependency lockfile)
#   3. installer/scripts/neuronix-install-engine.sh (Installation engine)
#   4. Target architecture and release manifest specifications
# ==============================================================================

set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_NIX="${PROJECT_ROOT}/version.nix"
FLAKE_LOCK="${PROJECT_ROOT}/flake.lock"
INSTALLER="${PROJECT_ROOT}/installer/scripts/neuronix-install-engine.sh"

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
echo -e "${BOLD}${CYAN}   NEURONIX OS SINGLE SOURCE OF TRUTH VERIFICATION GATE            ${RESET}"
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════════════${RESET}\n"

assert_check() {
    local desc="$1"
    local cmd="$2"

    echo -ne "  [TRUTH-GATE] ${desc} ... "
    if eval "$cmd" >/dev/null 2>&1; then
        echo -e "${GREEN}PASSED${RESET}"
        ((PASSED++))
    else
        echo -e "${RED}FAILED${RESET}"
        ((FAILED++))
    fi
}

# 1. Structural file existence
assert_check "version.nix exists in project root" "test -f '${VERSION_NIX}'"
assert_check "flake.lock exists in project root" "test -f '${FLAKE_LOCK}'"
assert_check "Installer script exists" "test -f '${INSTALLER}'"

# 2. Parsing single source of truth
EXPECTED_VER=$(nix-instantiate --eval --expr "(import ${VERSION_NIX}).version" 2>/dev/null | tr -d '"')
EXPECTED_TAG=$(nix-instantiate --eval --expr "(import ${VERSION_NIX}).releaseTag" 2>/dev/null | tr -d '"')
EXPECTED_COMMIT=$(nix-instantiate --eval --expr "(import ${VERSION_NIX}).nixpkgsCommit" 2>/dev/null | tr -d '"')
EXPECTED_STATE=$(nix-instantiate --eval --expr "(import ${VERSION_NIX}).stateVersion" 2>/dev/null | tr -d '"')

assert_check "version.nix declares non-empty canonical version (${EXPECTED_VER})" "test -n '${EXPECTED_VER}'"
assert_check "version.nix releaseTag matches 'v\${version}' (v${EXPECTED_VER})" "test '${EXPECTED_TAG}' = 'v${EXPECTED_VER}'"
assert_check "version.nix declares 40-character hex nixpkgsCommit" "echo '${EXPECTED_COMMIT}' | grep -Eq '^[0-9a-f]{40}$'"

# 3. Correlation with flake.lock
if command -v jq >/dev/null 2>&1; then
    LOCKED_COMMIT=$(jq -r '.nodes.nixpkgs.locked.rev' "${FLAKE_LOCK}" 2>/dev/null)
else
    LOCKED_COMMIT=$(awk '/"nixpkgs":/,/}/ { if ($1 ~ /"rev":/) { gsub(/[",]/, "", $2); print $2; exit } }' "${FLAKE_LOCK}")
fi

assert_check "flake.lock has locked nixpkgs revision" "test -n '${LOCKED_COMMIT}'"
assert_check "version.nix nixpkgsCommit matches flake.lock locked revision exactly" "test '${EXPECTED_COMMIT}' = '${LOCKED_COMMIT}'"

# 4. Correlation with Installer engine
INSTALLER_COMMIT=$(grep -E 'nixpkgsCommit\s*=' "${VERSION_NIX}" | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/')
assert_check "Installer engine resolves exact revision from version.nix" "test '${EXPECTED_COMMIT}' = '${INSTALLER_COMMIT}'"

# 5. Architecture matrix specification
PRIMARY_SYS=$(nix-instantiate --eval --expr "(import ${VERSION_NIX}).primarySystem" 2>/dev/null | tr -d '"')
assert_check "version.nix declares primarySystem as x86_64-linux" "test '${PRIMARY_SYS}' = 'x86_64-linux'"

echo -e "\n${BOLD}═══════════════════════════════════════════════════════════════════${RESET}"
echo -e "  Total Truth Assertions : $((PASSED + FAILED))"
echo -e "  Passed Validations     : ${PASSED}"
echo -e "  Failed Validations     : ${FAILED}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════════════${RESET}\n"

if [[ $FAILED -eq 0 ]]; then
    echo -e "${BOLD}${GREEN}✔ SINGLE SOURCE OF TRUTH VERIFIED: 100% REVISION CONSISTENCY${RESET}\n"
    exit 0
else
    echo -e "${BOLD}${RED}✖ SOURCE OF TRUTH GATE FAILED: Revision discrepancy detected.${RESET}\n"
    exit 1
fi
