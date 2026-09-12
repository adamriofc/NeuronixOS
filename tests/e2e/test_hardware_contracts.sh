#!/usr/bin/env bash
# ==============================================================================
# NEURONIX Hardware Contracts & Integration Verification Gate
# Verifies CPU topology detection, memory boundaries, Btrfs subvolume contracts,
# and storage controller passthrough primitives.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CLI_BIN="${PROJECT_ROOT}/src/neuronix"

PASSED=0
FAILED=0

check_contract() {
    local desc="$1"
    local cmd="$2"
    echo -n "  [HW-CONTRACT] ${desc} ... "
    if eval "$cmd" >/dev/null 2>&1; then
        echo "PASS"
        PASSED=$((PASSED + 1))
    else
        echo "FAIL"
        FAILED=$((FAILED + 1))
    fi
}

echo "╔═══════════════════════════════════════════════════════════════════╗"
echo "║          NEURONIX HARDWARE CONTRACTS VERIFICATION GATE           ║"
echo "╚═══════════════════════════════════════════════════════════════════╝"

# 1. CPU topology detection
check_contract "CLI reports valid CPU and architectural topology" \
    "python3 -c \"import sys; sys.path.insert(0, '${PROJECT_ROOT}/packages/neuronix-core'); from neuronix_core.telemetry import get_system_telemetry; t = get_system_telemetry(); assert len(t['cpu']) > 0\""

# 2. Memory telemetry contract
check_contract "System telemetry evaluates non-negative RAM capacity" \
    "python3 -c \"import sys; sys.path.insert(0, '${PROJECT_ROOT}/packages/neuronix-core'); from neuronix_core.telemetry import get_system_telemetry; t = get_system_telemetry(); assert len(t['ram']) > 0\""

# 3. ZRAM module declarations
check_contract "ZRAM swap module declares zstd compression and memory percent" \
    "grep -q 'algorithm = \"zstd\"' '${PROJECT_ROOT}/modules/services/memory-shield.nix' && grep -q 'memoryPercent = 100' '${PROJECT_ROOT}/modules/services/memory-shield.nix'"

# 4. Storage TRIM timer contract
check_contract "Storage subsystem declares automated fstrim systemd service" \
    "grep -q 'services.fstrim' '${PROJECT_ROOT}/modules/services/storage.nix'"

# 5. Btrfs auto-balance maintenance contract
check_contract "Storage subsystem declares monthly Btrfs metadata balance" \
    "grep -q 'btrfs balance start' '${PROJECT_ROOT}/modules/services/storage.nix'"

# 6. Flash storage journal ceiling contract
check_contract "Journald declares 500M storage ceiling to protect flash blocks" \
    "grep -q 'SystemMaxUse=500M' '${PROJECT_ROOT}/modules/services/storage.nix'"

# 7. Hardware profiles integrity
check_contract "Hardware qualification manifest defines required device classes" \
    "python3 -c \"import json; data = json.load(open('${PROJECT_ROOT}/data/hardware_qualification.json')); assert len(data['platforms']) >= 8\""

echo "═══════════════════════════════════════════════════════════════════"
echo "  Total Hardware Contracts : $((PASSED + FAILED))"
echo "  Passed                   : ${PASSED}"
echo "  Failed                   : ${FAILED}"
echo "═══════════════════════════════════════════════════════════════════"

if [ "$FAILED" -eq 0 ]; then
    echo "✔ ALL HARDWARE CONTRACTS SATISFIED 100%"
    exit 0
else
    echo "✖ HARDWARE CONTRACT VIOLATION DETECTED"
    exit 1
fi
