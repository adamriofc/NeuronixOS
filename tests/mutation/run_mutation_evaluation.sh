#!/usr/bin/env bash
# ==============================================================================
# NEURONIX OS Comprehensive Mutation Testing & Fault Injection Engine
# Systematically verifies that defensive gates, type constraints, and security
# firewalls actively kill deliberate code and configuration mutations.
#
# Copyright (c) 2026 NEURONIX Contributors
# Licensed under the Apache License, Version 2.0
# ==============================================================================

set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLI_BIN="${PROJECT_ROOT}/src/neuronix"
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
echo -e "${BOLD}${CYAN}║     NEURONIX OS COMPREHENSIVE MUTATION EVALUATION HARNESS         ║${RESET}"
echo -e "${BOLD}${CYAN}║    Injecting Deliberate Fault Mutants Across System Layers        ║${RESET}"
echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════════════════════════════════╝${RESET}\n"

mutation_eval() {
    local mutant_id="$1"
    local desc="$2"
    local condition="$3"

    echo -ne "  [MUTANT ${mutant_id}] ${desc} ... "
    if eval "$condition"; then
        echo -e "${GREEN}KILLED (PASS)${RESET}"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}SURVIVED (FAIL)${RESET}"
        FAILED=$((FAILED + 1))
    fi
}

# Mutant M1: Command-line argument injection into package verifier
mutation_eval "M1" "Shell payload injection into CLI verify command" \
    "! bash '${CLI_BIN}' verify 'malicious; rm -rf /' >/dev/null 2>&1"

# Mutant M2: Directory traversal in installer username
mutation_eval "M2" "Directory traversal sequence in installer username parameter" \
    "! TARGET_USER='../../../root' bash '${INSTALLER_BIN}' >/dev/null 2>&1"

# Mutant M3: RFC 1123 hostname invalid character injection
mutation_eval "M3" "RFC 1123 violation in installer hostname parameter" \
    "! TARGET_HOSTNAME='bad_host_$$!' bash '${INSTALLER_BIN}' >/dev/null 2>&1"

# Mutant M4: Unsupported desktop environment flag in installer
mutation_eval "M4" "Unknown desktop environment target in installer" \
    "! SELECTED_DESKTOP='unsupported_de_environment' bash '${INSTALLER_BIN}' >/dev/null 2>&1"

# Mutant M5: Unauthorized command execution via privileged dispatcher
test_unauthorized_dispatcher() {
    (
        source "${CLI_BIN}"
        run_privileged "cat /etc/shadow" >/dev/null 2>&1
    )
}
mutation_eval "M5" "Arbitrary binary execution via run_privileged wrapper" \
    "! test_unauthorized_dispatcher"

# Mutant M6: Signature bit-flip mutant rejection
test_crypto_bitflip() {
    python3 -c "
import sys, os
sys.path.insert(0, '${PROJECT_ROOT}/packages/neuronix-core')
from neuronix_core.crypto import generate_keypair, sign_bytes, verify_bytes
pk, sk = generate_keypair()
msg = b'canonical-payload'
sig = sign_bytes(msg, sk)
sig_bytes = bytearray(bytes.fromhex(sig))
sig_bytes[0] ^= 0x01
sys.exit(0 if not verify_bytes(msg, sig_bytes.hex(), pk) else 1)
" >/dev/null 2>&1
}
mutation_eval "M6" "Ed25519 signature bit-flip mutation rejection" \
    "test_crypto_bitflip"

# Mutant M7: Storage firewall factor bypass mutant (bad confirmation token)
test_storage_token_bypass() {
    python3 -c "
import sys
sys.path.insert(0, '${PROJECT_ROOT}/packages/neuronix-core')
from neuronix_core.storage_planner import StorageFirewall
allowed, reason, factors = StorageFirewall.evaluate_7_factors(
    target_device='/dev/vdz',
    plan_hash='hash123',
    expected_plan_hash='hash123',
    confirmation_token='BAD_TOKEN',
    operator_auth={'operator_id': 'admin@sys', 'clearance': 'STORAGE_ADMIN', 'signature': 'valid'},
    simulated_entropy=True,
    active_mounts_override=[],
    active_devices_override=set()
)
# Mutant is killed if allowed is False
sys.exit(0 if not allowed else 1)
" >/dev/null 2>&1
}
mutation_eval "M7" "Storage firewall confirmation token bypass rejection" \
    "test_storage_token_bypass"

# Mutant M8: Boot health out-of-order phase transition mutant
test_boot_health_ooo() {
    python3 -c "
import sys
sys.path.insert(0, '${PROJECT_ROOT}/packages/neuronix-core')
from neuronix_core.boot_trust import BootHealthContract
contract = BootHealthContract()
# Attempt invalid out-of-order jump directly to DESKTOP_TARGET
ok = contract.advance_stage('DESKTOP_TARGET')
# Mutant is killed if ok is False
sys.exit(0 if not ok else 1)
" >/dev/null 2>&1
}
mutation_eval "M8" "Boot health contract out-of-order phase skip rejection" \
    "test_boot_health_ooo"

# Mutant M9: OCI untrusted container CAP_SYS_ADMIN bounding strip
test_oci_cap_leak() {
    python3 -c "
import sys, os, json
sys.path.insert(0, '${PROJECT_ROOT}/packages/neuronix-core')
from neuronix_core.uef.oci_provider import OciContainerProvider, WorkloadSpec
provider = OciContainerProvider()
workload = WorkloadSpec('wl-test', 'rootfs-dir', ['/bin/sh'], rootfs_path='/')
prep = provider.prepare(workload)
config_path = os.path.join(prep.temp_dir, 'config.json')
with open(config_path) as f:
    spec = json.load(f)
provider.cleanup(prep)
caps = spec.get('process', {}).get('capabilities', {}).get('bounding', [])
# CAP_SYS_ADMIN must be strictly absent
sys.exit(0 if 'CAP_SYS_ADMIN' not in caps else 1)
" >/dev/null 2>&1
}
mutation_eval "M9" "OCI untrusted container CAP_SYS_ADMIN bounding strip" \
    "test_oci_cap_leak"

# Mutant M10: OCI noNewPrivileges enforcement mutant
test_oci_nonewprivs() {
    python3 -c "
import sys, os, json
sys.path.insert(0, '${PROJECT_ROOT}/packages/neuronix-core')
from neuronix_core.uef.oci_provider import OciContainerProvider, WorkloadSpec
provider = OciContainerProvider()
workload = WorkloadSpec('wl-test', 'rootfs-dir', ['/bin/sh'], rootfs_path='/')
prep = provider.prepare(workload)
config_path = os.path.join(prep.temp_dir, 'config.json')
with open(config_path) as f:
    spec = json.load(f)
provider.cleanup(prep)
nonewprivs = spec.get('process', {}).get('noNewPrivileges', False)
# Mutant killed if noNewPrivileges is True
sys.exit(0 if nonewprivs is True else 1)
" >/dev/null 2>&1
}
mutation_eval "M10" "OCI untrusted container noNewPrivileges mandatory enforcement" \
    "test_oci_nonewprivs"

echo -e "\n${BOLD}═══════════════════════════════════════════════════════════════════${RESET}"
echo -e "  Total Fault Mutants Evaluated  : $((PASSED + FAILED))"
echo -e "  Mutants Successfully Killed    : ${PASSED}"
echo -e "  Mutants Survived (Defects)     : ${FAILED}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════════════${RESET}\n"

if [[ $FAILED -eq 0 ]]; then
    echo -e "${BOLD}${GREEN}✔ 100% MUTATION RESILIENCE ACHIEVED: ALL 10 MUTANTS KILLED${RESET}\n"
    exit 0
else
    echo -e "${BOLD}${RED}✖ MUTATION TESTING DETECTED DEFENSIVE REGRESSIONS${RESET}\n"
    exit 1
fi
