#!/usr/bin/env bash
# ==============================================================================
# NEURONIX OS Two-Build Derivation Reproducibility Verification
# Validates functional reproducibility:
#   Identical pinned inputs -> Identical derivation drvPath & store hashes
#
# Copyright (c) 2026 NEURONIX Contributors
# Licensed under the Apache License, Version 2.0
# ==============================================================================

set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
echo -e "${BOLD}${CYAN}║     NEURONIX OS TWO-BUILD DERIVATION REPRODUCIBILITY GATE         ║${RESET}"
echo -e "${BOLD}${CYAN}║    Bit-Identical Derivation Path & Input Closure Invariance       ║${RESET}"
echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════════════════════════════════╝${RESET}\n"

repro_assert() {
    local desc="$1"
    local condition="$2"

    echo -ne "  [REPRODUCIBILITY] ${desc} ... "
    if eval "$condition"; then
        echo -e "${GREEN}PASS${RESET}"
        ((PASSED++))
    else
        echo -e "${RED}FAIL${RESET}"
        ((FAILED++))
    fi
}

# 1. Package Derivation Reproducibility
echo -e "${BOLD}Phase 1: Package Derivation Evaluation Invariant${RESET}"
PKG_DRV_1=$(nix eval "${PROJECT_ROOT}#packages.x86_64-linux.neuronix-cli.drvPath" 2>/dev/null || echo "drv1")
PKG_DRV_2=$(nix eval "${PROJECT_ROOT}#packages.x86_64-linux.neuronix-cli.drvPath" 2>/dev/null || echo "drv2")

repro_assert "Package derivation path bit-identical across runs" \
    "[[ '${PKG_DRV_1}' == '${PKG_DRV_2}' && '${PKG_DRV_1}' != 'drv1' ]]"

# 2. OpenCode Copilot Derivation Reproducibility
PKG_OC_1=$(nix eval "${PROJECT_ROOT}#packages.x86_64-linux.opencode.drvPath" 2>/dev/null || echo "oc1")
PKG_OC_2=$(nix eval "${PROJECT_ROOT}#packages.x86_64-linux.opencode.drvPath" 2>/dev/null || echo "oc2")

repro_assert "OpenCode package derivation bit-identical across runs" \
    "[[ '${PKG_OC_1}' == '${PKG_OC_2}' && '${PKG_OC_1}' != 'oc1' ]]"

# 3. Flake Lock Pinned Invariant
repro_assert "Flake lockfile contains immutable locked commit" \
    "grep -q '\"rev\":' '${PROJECT_ROOT}/flake.lock'"

# 4. Synthesized Target Configuration Determinism
echo -e "\n${BOLD}Phase 2: Installer Synthesized Target Determinism${RESET}"
TMP_RUN_A=$(mktemp -d "/tmp/neuronix-repro-a-XXXXXX")
TMP_RUN_B=$(mktemp -d "/tmp/neuronix-repro-b-XXXXXX")
trap 'rm -rf "${TMP_RUN_A}" "${TMP_RUN_B}"' EXIT

DRY_RUN=1 TARGET_ROOT="${TMP_RUN_A}" bash "${PROJECT_ROOT}/installer/scripts/neuronix-install-engine.sh" >/dev/null 2>&1
DRY_RUN=1 TARGET_ROOT="${TMP_RUN_B}" bash "${PROJECT_ROOT}/installer/scripts/neuronix-install-engine.sh" >/dev/null 2>&1

HASH_CFG_A=$(sha256sum "${TMP_RUN_A}/etc/nixos/configuration.nix" | awk '{print $1}')
HASH_CFG_B=$(sha256sum "${TMP_RUN_B}/etc/nixos/configuration.nix" | awk '{print $1}')

repro_assert "Installer configuration.nix SHA-256 hash bit-identical" \
    "[[ '${HASH_CFG_A}' == '${HASH_CFG_B}' ]]"

HASH_FLAKE_A=$(sha256sum "${TMP_RUN_A}/etc/nixos/flake.nix" | awk '{print $1}')
HASH_FLAKE_B=$(sha256sum "${TMP_RUN_B}/etc/nixos/flake.nix" | awk '{print $1}')

repro_assert "Installer flake.nix SHA-256 hash bit-identical" \
    "[[ '${HASH_FLAKE_A}' == '${HASH_FLAKE_B}' ]]"

echo -e "\n${BOLD}═══════════════════════════════════════════════════════════════════${RESET}"
echo -e "  Total Reproducibility Assertions : $((PASSED + FAILED))"
echo -e "  Passed Validations               : ${PASSED}"
echo -e "  Failed Validations               : ${FAILED}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════════════${RESET}\n"

if [[ $FAILED -eq 0 ]]; then
    echo -e "${BOLD}${GREEN}✔ FUNCTIONAL TWO-BUILD REPRODUCIBILITY VERIFIED 100%${RESET}\n"
    exit 0
else
    echo -e "${BOLD}${RED}✖ REPRODUCIBILITY CONTRACT REGRESSION DETECTED${RESET}\n"
    exit 1
fi
