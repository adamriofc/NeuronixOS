#!/usr/bin/env bash
# ==============================================================================
# NEURONIX OS Unified E2E ISO Installation & Lifecycle Orchestrator
# Orchestrates:
#   1. [CONTRACT-GATE] Hermetic AST, Flake, and API Invariant Gates
#   2. [REAL-E2E-GATE] Hardware-Accelerated QEMU/KVM Storage and Rollback Lifecycle
#
# Copyright (c) 2026 NEURONIX Contributors
# Licensed under the Apache License, Version 2.0
# ==============================================================================

set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIST_DIR="${PROJECT_ROOT}/dist"
EVIDENCE_FILE="${DIST_DIR}/e2e_evidence.json"
CONTRACT_SCRIPT="${PROJECT_ROOT}/tests/e2e/contract/test_iso_contract.sh"
REAL_SCRIPT="${PROJECT_ROOT}/tests/e2e/real/test_real_e2e_lifecycle.sh"

mkdir -p "${DIST_DIR}"

REQUESTED_MODE="auto"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)
            REQUESTED_MODE="$2"
            shift 2
            ;;
        --contract)
            REQUESTED_MODE="contract"
            shift
            ;;
        --real-e2e)
            REQUESTED_MODE="real_e2e"
            shift
            ;;
        --all)
            REQUESTED_MODE="all"
            shift
            ;;
        *)
            shift
            ;;
    esac
done

KVM_AVAILABLE=false
if [[ -e /dev/kvm && -r /dev/kvm && -w /dev/kvm ]]; then
    KVM_AVAILABLE=true
fi

QEMU_AVAILABLE=false
if command -v qemu-system-x86_64 >/dev/null 2>&1 || ls /nix/store/*-qemu-*/bin/qemu-system-x86_64 /nix/store/*-qemu-host-cpu-only-*/bin/qemu-system-x86_64 >/dev/null 2>&1; then
    QEMU_AVAILABLE=true
fi

# Determine target execution modes
RUN_CONTRACT=false
RUN_REAL=false

case "$REQUESTED_MODE" in
    contract)
        RUN_CONTRACT=true
        ;;
    real_e2e)
        RUN_REAL=true
        ;;
    all)
        RUN_CONTRACT=true
        RUN_REAL=true
        ;;
    auto)
        RUN_CONTRACT=true
        if [[ "$KVM_AVAILABLE" == "true" && "$QEMU_AVAILABLE" == "true" ]]; then
            RUN_REAL=true
        fi
        ;;
    *)
        echo "Unknown mode: $REQUESTED_MODE (allowed: contract, real_e2e, all, auto)" >&2
        exit 2
        ;;
esac

# Terminal colors
if [[ -t 1 ]]; then
    GREEN="\033[32m"
    RED="\033[31m"
    YELLOW="\033[33m"
    CYAN="\033[36m"
    BOLD="\033[1m"
    RESET="\033[0m"
else
    GREEN=""
    RED=""
    YELLOW=""
    CYAN=""
    BOLD=""
    RESET=""
fi

echo -e "\n${BOLD}${CYAN}╔═══════════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║    NEURONIX OS UNIFIED E2E INSTALLATION & LIFECYCLE GATE          ║${RESET}"
echo -e "${BOLD}${CYAN}║    Requested: ${REQUESTED_MODE} | Contract: ${RUN_CONTRACT} | Real E2E: ${RUN_REAL}        ║${RESET}"
echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════════════════════════════════╝${RESET}\n"

CONTRACT_EXIT=0
REAL_EXIT=0

if [[ "$RUN_CONTRACT" == "true" ]]; then
    if [[ -x "$CONTRACT_SCRIPT" ]]; then
        bash "$CONTRACT_SCRIPT" || CONTRACT_EXIT=$?
    else
        echo -e "${RED}Contract script missing: ${CONTRACT_SCRIPT}${RESET}" >&2
        CONTRACT_EXIT=1
    fi
fi

if [[ "$RUN_REAL" == "true" ]]; then
    if [[ "$KVM_AVAILABLE" != "true" || "$QEMU_AVAILABLE" != "true" ]]; then
        echo -e "${YELLOW}Hardware virtualization (KVM/QEMU) unavailable for REAL E2E.${RESET}"
        echo -e "${YELLOW}KVM: ${KVM_AVAILABLE}, QEMU: ${QEMU_AVAILABLE}${RESET}"
        if [[ "$REQUESTED_MODE" == "real_e2e" ]]; then
            REAL_EXIT=2
        fi
    else
        if [[ -x "$REAL_SCRIPT" ]]; then
            bash "$REAL_SCRIPT" || REAL_EXIT=$?
        else
            echo -e "${RED}Real E2E script missing: ${REAL_SCRIPT}${RESET}" >&2
            REAL_EXIT=1
        fi
    fi
fi

# Read subordinate evidence files if present
CONTRACT_EVIDENCE="{}"
if [[ -f "${DIST_DIR}/contract_e2e_evidence.json" ]]; then
    CONTRACT_EVIDENCE="$(cat "${DIST_DIR}/contract_e2e_evidence.json")"
fi

REAL_EVIDENCE="{}"
if [[ -f "${DIST_DIR}/real_e2e_evidence.json" ]]; then
    REAL_EVIDENCE="$(cat "${DIST_DIR}/real_e2e_evidence.json")"
fi

cat << JSON_EOF > "${EVIDENCE_FILE}"
{
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "requested_mode": "${REQUESTED_MODE}",
  "executed_contract": ${RUN_CONTRACT},
  "executed_real": ${RUN_REAL},
  "kvm_available": ${KVM_AVAILABLE},
  "qemu_available": ${QEMU_AVAILABLE},
  "contract_exit_code": ${CONTRACT_EXIT},
  "real_exit_code": ${REAL_EXIT},
  "contract_evidence": ${CONTRACT_EVIDENCE},
  "real_evidence": ${REAL_EVIDENCE},
  "overall_status": "$([[ $CONTRACT_EXIT -eq 0 && $REAL_EXIT -eq 0 ]] && echo "PASSED" || echo "FAILED")"
}
JSON_EOF

echo -e "\n${BOLD}═══════════════════════════════════════════════════════════════════${RESET}"
echo -e "  Overall Orchestrator Status : $([[ $CONTRACT_EXIT -eq 0 && $REAL_EXIT -eq 0 ]] && echo -e "${GREEN}ALL GATES GREEN${RESET}" || echo -e "${RED}GATE FAILURE DETECTED${RESET}")"
echo -e "  Master Evidence File        : ${EVIDENCE_FILE}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════════════${RESET}\n"

if [[ $CONTRACT_EXIT -eq 0 && $REAL_EXIT -eq 0 ]]; then
    exit 0
else
    exit 1
fi
