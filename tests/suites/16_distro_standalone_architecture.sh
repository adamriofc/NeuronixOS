#!/usr/bin/env bash
# ==============================================================================
# Suite 16: Distro Standalone Architecture & Calamares Flake Engine (30 Tests)
# Validates Phase 4 Distribution Architecture, Modules, Calamares, CLI, and ADRs
# ==============================================================================

DISTRO_PATH="${PROJECT_ROOT}/Distro"
TARGET_BIN="${PROJECT_ROOT}/bin/neuronix"

start_suite "16 - Distro Standalone Architecture & Calamares Flake Engine"

# 1-6. Flake & Core Configuration Parsing
assert_eq "$(test -f "${DISTRO_PATH}/flake.nix" && echo "exists" || echo "missing")" "exists" "Distro flake.nix exists"
assert_exit_code "nix-instantiate --parse '${DISTRO_PATH}/flake.nix'" 0 "Distro flake.nix has valid Nix syntax"
assert_exit_code "nix-instantiate --parse '${DISTRO_PATH}/hosts/iso/default.nix'" 0 "Live ISO host config has valid Nix syntax"
assert_exit_code "nix-instantiate --parse '${DISTRO_PATH}/hosts/desktop/default.nix'" 0 "Desktop host config has valid Nix syntax"
assert_exit_code "nix-instantiate --parse '${DISTRO_PATH}/modules/core/default.nix'" 0 "Core module has valid Nix syntax"
assert_exit_code "nix-instantiate --parse '${DISTRO_PATH}/modules/services/memory-shield.nix'" 0 "Memory-shield module has valid Nix syntax"

# 7-12. 27-Pillars Key Declarative Encodings
assert_output_contains "grep -F 'allowUnfree = true' '${DISTRO_PATH}/modules/core/default.nix'" "allowUnfree = true" "Pilar 1 allowUnfree is declared"
assert_output_contains "grep -F 'time.hardwareClockInLocalTime' '${DISTRO_PATH}/modules/hardware/boot.nix'" "time.hardwareClockInLocalTime" "Pilar 2 & 11 RTC Local Time sync is declared"
assert_output_contains "grep -F 'btrfs-balance' '${DISTRO_PATH}/modules/services/storage.nix'" "btrfs-balance" "Pilar 3 Btrfs balance timer is declared"
assert_output_contains "grep -F 'configurationLimit = 15' '${DISTRO_PATH}/modules/hardware/boot.nix'" "configurationLimit = 15" "Pilar 5 ESP limit 15 is declared"
assert_output_contains "grep -F 'hardware.enableAllFirmware' '${DISTRO_PATH}/modules/hardware/firmware.nix'" "hardware.enableAllFirmware" "Pilar 6 Wi-Fi firmware is declared"
assert_output_contains "grep -F 'zramSwap' '${DISTRO_PATH}/modules/services/memory-shield.nix'" "zramSwap" "Pilar 17 ZRAM swap is declared"

# 13-18. Calamares Declarative Installer Engine Invariants
assert_eq "$(test -x "${DISTRO_PATH}/installer/scripts/neuronix-install-engine.sh" && echo "exec" || echo "non-exec")" "exec" "neuronix-install-engine.sh is executable"
INSTALL_OUT=$(DRY_RUN=1 bash "${DISTRO_PATH}/installer/scripts/neuronix-install-engine.sh" 2>&1)
assert_output_contains "echo '$INSTALL_OUT'" "Verifikasi dry-run sukses" "Installer engine dry-run completes successfully"
assert_eq "$(test -f "/tmp/neuronix-mock-install/etc/nixos/flake.nix" && echo "exists" || echo "missing")" "exists" "Installer generates clean flake.nix"
assert_eq "$(test -f "/tmp/neuronix-mock-install/etc/nixos/configuration.nix" && echo "exists" || echo "missing")" "exists" "Installer generates clean configuration.nix"
assert_exit_code "nix-instantiate --parse '/tmp/neuronix-mock-install/etc/nixos/configuration.nix'" 0 "Generated configuration.nix has valid Nix syntax"
assert_output_contains "grep -F 'btrfsSubvolumes' '${DISTRO_PATH}/installer/calamares/modules/partition.conf'" "btrfsSubvolumes" "Calamares partition.conf declares Btrfs subvolumes"

# 19-24. One-Command Dev Stacks (CLI neuronix dev)
assert_exit_code "DEV_DRY_RUN=1 $TARGET_BIN dev python" 0 "neuronix dev python validates toolchain"
assert_exit_code "DEV_DRY_RUN=1 $TARGET_BIN dev rust" 0 "neuronix dev rust validates toolchain"
assert_exit_code "DEV_DRY_RUN=1 $TARGET_BIN dev node" 0 "neuronix dev node validates toolchain"
assert_exit_code "DEV_DRY_RUN=1 $TARGET_BIN dev ai" 0 "neuronix dev ai validates toolchain"
assert_exit_code "DEV_DRY_RUN=1 $TARGET_BIN dev go" 0 "neuronix dev go validates toolchain"
assert_exit_code "$TARGET_BIN dev nonexistent_stack 2>/dev/null" 1 "Invalid stack rejected deterministically"

# 25-28. NEURONIX Center Telemetry & ADRs
CENTER_OUT=$(nix-shell -p python3 --run "python3 '${DISTRO_PATH}/packages/neuronix-center/neuronix_center.py' --cli" 2>&1)
assert_output_contains "echo '$CENTER_OUT'" "NEURONIX CONTROL CENTER" "neuronix-center banner emitted in CLI mode"
assert_output_contains "echo '$CENTER_OUT'" "Generasi Aktif" "neuronix-center telemetry inspects active generation"
assert_eq "$(test -f "${DISTRO_PATH}/docs/adr/ADR-001-why-flakes.md" && echo "exists" || echo "missing")" "exists" "ADR-001 exists"
assert_eq "$(test -f "${DISTRO_PATH}/docs/adr/ADR-002-why-calamares-flake-generator.md" && echo "exists" || echo "missing")" "exists" "ADR-002 exists"

# 29-30. Sanitization & Zero Local Path Invariants
COUNT_DRIVE_D=$( (grep -rn "Drive D" "${DISTRO_PATH}" 2>/dev/null || true) | (grep -v "/tests/" || true) | wc -l)
assert_eq "$COUNT_DRIVE_D" "0" "Zero occurrences of 'Drive D' across Distro files"
COUNT_USER_PATH=$( (grep -rn "/home/adamrofc" "${DISTRO_PATH}" 2>/dev/null || true) | (grep -v "/tests/" || true) | wc -l)
assert_eq "$COUNT_USER_PATH" "0" "Zero hardcoded user paths across Distro source files"
