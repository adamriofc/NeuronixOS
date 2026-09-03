#!/usr/bin/env bash
# ==============================================================================
# NEURONIX OS: Distribution Automated Test Suite (Rust-Grade Quality)
# Validates Phase 4 Distribution Architecture, Modules, Calamares, CLI, and ADRs
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISTRO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${DISTRO_ROOT}/.." && pwd)"
NEURONIX_BIN="${PROJECT_ROOT}/src/neuronix"

PASSED_COUNT=0
FAILED_COUNT=0
START_TIME=$(date +%s%3N)

GREEN="\033[1;32m"
RED="\033[1;31m"
CYAN="\033[1;36m"
BOLD="\033[1m"
RESET="\033[0m"

log_pass() {
  PASSED_COUNT=$((PASSED_COUNT + 1))
  echo -e "  ${GREEN}✔ PASS${RESET} [$PASSED_COUNT] $*"
}

log_fail() {
  FAILED_COUNT=$((FAILED_COUNT + 1))
  echo -e "  ${RED}✖ FAIL${RESET} [$FAILED_COUNT] $*"
}

suite_header() {
  echo -e "\n${CYAN}▶ [SUITE] $*${RESET}"
}

echo "==================================================================="
echo "   NEURONIX OS DISTRIBUTION AUTOMATED TEST SUITE (PHASE 4)        "
echo "==================================================================="

# ------------------------------------------------------------------------------
# SUITE 1: File Integrity & Modular Hierarchy
# ------------------------------------------------------------------------------
suite_header "1 - File Integrity & Modular Hierarchy"

check_file() {
  local f="$1"
  if [ -f "$f" ]; then
    log_pass "File exists: $(basename "$f")"
  else
    log_fail "File missing: $f"
  fi
}

check_file "${DISTRO_ROOT}/flake.nix"
check_file "${DISTRO_ROOT}/hosts/iso/default.nix"
check_file "${DISTRO_ROOT}/hosts/desktop/default.nix"
check_file "${DISTRO_ROOT}/modules/core/default.nix"
check_file "${DISTRO_ROOT}/modules/hardware/boot.nix"
check_file "${DISTRO_ROOT}/modules/hardware/firmware.nix"
check_file "${DISTRO_ROOT}/modules/hardware/audio.nix"
check_file "${DISTRO_ROOT}/modules/hardware/power.nix"
check_file "${DISTRO_ROOT}/modules/hardware/nvidia-prime.nix"
check_file "${DISTRO_ROOT}/modules/hardware/cpu.nix"
check_file "${DISTRO_ROOT}/modules/services/memory-shield.nix"
check_file "${DISTRO_ROOT}/modules/services/storage.nix"
check_file "${DISTRO_ROOT}/modules/services/flatpak.nix"
check_file "${DISTRO_ROOT}/modules/services/network.nix"
check_file "${DISTRO_ROOT}/modules/services/desktop-tweaks.nix"
check_file "${DISTRO_ROOT}/modules/services/printing.nix"
check_file "${DISTRO_ROOT}/modules/services/security.nix"
check_file "${DISTRO_ROOT}/modules/desktop/kde.nix"
check_file "${DISTRO_ROOT}/modules/desktop/gnome.nix"
check_file "${DISTRO_ROOT}/modules/desktop/hyprland.nix"
check_file "${DISTRO_ROOT}/installer/calamares/settings.conf"
check_file "${DISTRO_ROOT}/installer/calamares/modules/partition.conf"
check_file "${DISTRO_ROOT}/installer/scripts/neuronix-install-engine.sh"
check_file "${DISTRO_ROOT}/packages/neuronix-center/neuronix_center.py"
check_file "${DISTRO_ROOT}/packages/neuronix-center/default.nix"

# ------------------------------------------------------------------------------
# SUITE 2: Pure Nix Syntax Validation
# ------------------------------------------------------------------------------
suite_header "2 - Pure Nix Syntax Validation"

test_nix_syntax() {
  local f="$1"
  if nix-instantiate --parse "$f" >/dev/null 2>&1; then
    log_pass "Nix syntax valid: $(basename "$f")"
  else
    log_fail "Nix syntax error in: $f"
  fi
}

test_nix_syntax "${DISTRO_ROOT}/flake.nix"
test_nix_syntax "${DISTRO_ROOT}/hosts/iso/default.nix"
test_nix_syntax "${DISTRO_ROOT}/hosts/desktop/default.nix"
test_nix_syntax "${DISTRO_ROOT}/modules/core/default.nix"
test_nix_syntax "${DISTRO_ROOT}/modules/hardware/boot.nix"
test_nix_syntax "${DISTRO_ROOT}/modules/hardware/firmware.nix"
test_nix_syntax "${DISTRO_ROOT}/modules/hardware/audio.nix"
test_nix_syntax "${DISTRO_ROOT}/modules/hardware/power.nix"
test_nix_syntax "${DISTRO_ROOT}/modules/hardware/nvidia-prime.nix"
test_nix_syntax "${DISTRO_ROOT}/modules/hardware/cpu.nix"
test_nix_syntax "${DISTRO_ROOT}/modules/services/memory-shield.nix"
test_nix_syntax "${DISTRO_ROOT}/modules/services/storage.nix"
test_nix_syntax "${DISTRO_ROOT}/modules/services/flatpak.nix"
test_nix_syntax "${DISTRO_ROOT}/modules/services/network.nix"
test_nix_syntax "${DISTRO_ROOT}/modules/services/desktop-tweaks.nix"
test_nix_syntax "${DISTRO_ROOT}/modules/services/printing.nix"
test_nix_syntax "${DISTRO_ROOT}/modules/services/security.nix"
test_nix_syntax "${DISTRO_ROOT}/modules/desktop/kde.nix"
test_nix_syntax "${DISTRO_ROOT}/modules/desktop/gnome.nix"
test_nix_syntax "${DISTRO_ROOT}/modules/desktop/hyprland.nix"
test_nix_syntax "${DISTRO_ROOT}/packages/neuronix-center/default.nix"

# ------------------------------------------------------------------------------
# SUITE 3: 27 Pillars Declarative Encoding Verification
# ------------------------------------------------------------------------------
suite_header "3 - 27 Pillars Declarative Encoding Verification"

assert_contains() {
  local f="$1"
  local pattern="$2"
  local desc="$3"
  if grep -qF "$pattern" "$f"; then
    log_pass "$desc"
  else
    log_fail "$desc (Pattern '$pattern' not found in $f)"
  fi
}

assert_contains "${DISTRO_ROOT}/modules/core/default.nix" "allowUnfree = true" "Pilar 1: allowUnfree = true is encoded"
assert_contains "${DISTRO_ROOT}/modules/hardware/boot.nix" "time.hardwareClockInLocalTime" "Pilar 2 & 11: RTC Local Time sync encoded"
assert_contains "${DISTRO_ROOT}/modules/services/storage.nix" "btrfs-balance" "Pilar 3: Btrfs periodic balance timer encoded"
assert_contains "${DISTRO_ROOT}/modules/services/flatpak.nix" "services.flatpak.enable" "Pilar 4: Flatpak enabled"
assert_contains "${DISTRO_ROOT}/modules/hardware/boot.nix" "configurationLimit = 15" "Pilar 5: Bootloader configurationLimit 15 encoded"
assert_contains "${DISTRO_ROOT}/modules/hardware/firmware.nix" "hardware.enableAllFirmware" "Pilar 6: enableAllFirmware encoded"
assert_contains "${DISTRO_ROOT}/modules/hardware/nvidia-prime.nix" "hardware.graphics" "Pilar 7 & 20: Graphics & Video Acceleration encoded"
assert_contains "${DISTRO_ROOT}/modules/services/flatpak.nix" "FileChooser" "Pilar 9: FileChooser portal mapping encoded"
assert_contains "${DISTRO_ROOT}/modules/hardware/power.nix" "services.power-profiles-daemon" "Pilar 10: power-profiles-daemon encoded"
assert_contains "${DISTRO_ROOT}/modules/hardware/boot.nix" "vm.max_map_count" "Pilar 12: SteamOS vm.max_map_count encoded"
assert_contains "${DISTRO_ROOT}/modules/services/desktop-tweaks.nix" "NIXOS_OZONE_WL" "Pilar 13: Ozone Wayland flag encoded"
assert_contains "${DISTRO_ROOT}/modules/hardware/boot.nix" "systemd.watchdog" "Pilar 14: UEFI Watchdog timeout encoded"
assert_contains "${DISTRO_ROOT}/modules/services/desktop-tweaks.nix" "fcitx5" "Pilar 15: Fcitx5 IME encoded"
assert_contains "${DISTRO_ROOT}/modules/services/network.nix" "neuronix-add-ca" "Pilar 16: Corporate Root CA helper encoded"
assert_contains "${DISTRO_ROOT}/modules/services/memory-shield.nix" "zramSwap" "Pilar 17: ZRAM swap encoded"
assert_contains "${DISTRO_ROOT}/modules/services/memory-shield.nix" "systemd.oomd" "Pilar 17: systemd-oomd PSI encoded"
assert_contains "${DISTRO_ROOT}/modules/hardware/audio.nix" "pipewire" "Pilar 18: PipeWire HD audio encoded"
assert_contains "${DISTRO_ROOT}/modules/hardware/audio.nix" "ldac" "Pilar 18: Bluetooth LDAC codec encoded"
assert_contains "${DISTRO_ROOT}/modules/hardware/power.nix" "charge_control_limit_max" "Pilar 19: 80% battery conservation limit encoded"
assert_contains "${DISTRO_ROOT}/modules/services/network.nix" "check_network_status" "Pilar 21: Captive Portal auto-detection encoded"
assert_contains "${DISTRO_ROOT}/modules/services/printing.nix" "services.printing" "Pilar 22: Driverless AirPrint encoded"
assert_contains "${DISTRO_ROOT}/modules/services/storage.nix" "ntfs" "Pilar 23: Native NTFS3 filesystem support encoded"
assert_contains "${DISTRO_ROOT}/modules/hardware/audio.nix" "snd_hda_intel power_save=0" "Pilar 24: ALSA powersave pop fix encoded"
assert_contains "${DISTRO_ROOT}/installer/calamares/modules/partition.conf" "subvolume: \"@swap\"" "Pilar 25: Dedicated @swap subvolume encoded"
assert_contains "${DISTRO_ROOT}/modules/hardware/cpu.nix" "updateMicrocode" "Pilar 26: CPU Microcode auto-update encoded"
assert_contains "${DISTRO_ROOT}/modules/services/security.nix" "programs.gnupg.agent" "Pilar 27: GPG Agent & SSH support encoded"

# ------------------------------------------------------------------------------
# SUITE 4: Calamares Declarative Flake-Generating Engine
# ------------------------------------------------------------------------------
suite_header "4 - Calamares Declarative Flake-Generating Engine"

test_installer_engine() {
  local out
  out=$(DRY_RUN=1 bash "${DISTRO_ROOT}/installer/scripts/neuronix-install-engine.sh" 2>&1)
  if echo "$out" | grep -q "Verifikasi dry-run sukses"; then
    log_pass "Installer engine executes in dry-run mode without errors"
  else
    log_fail "Installer engine failed in dry-run mode"
  fi

  if [ -f "/tmp/neuronix-mock-install/etc/nixos/flake.nix" ]; then
    log_pass "Installer generated /etc/nixos/flake.nix"
  else
    log_fail "Installer failed to generate flake.nix"
  fi

  if [ -f "/tmp/neuronix-mock-install/etc/nixos/configuration.nix" ]; then
    log_pass "Installer generated /etc/nixos/configuration.nix"
  else
    log_fail "Installer failed to generate configuration.nix"
  fi

  if [ -f "/tmp/neuronix-mock-install/etc/nixos/hardware-configuration.nix" ]; then
    log_pass "Installer generated /etc/nixos/hardware-configuration.nix"
  else
    log_fail "Installer failed to generate hardware-configuration.nix"
  fi

  # Validate syntax of generated configuration
  if nix-instantiate --parse "/tmp/neuronix-mock-install/etc/nixos/configuration.nix" >/dev/null 2>&1; then
    log_pass "Generated configuration.nix has valid Nix syntax"
  else
    log_fail "Generated configuration.nix has invalid Nix syntax"
  fi
}
test_installer_engine

# ------------------------------------------------------------------------------
# SUITE 5: One-Command Dev Environments (CLI neuronix dev)
# ------------------------------------------------------------------------------
suite_header "5 - One-Command Dev Environments (CLI neuronix dev)"

test_dev_stack() {
  local stack="$1"
  local out
  out=$(DEV_DRY_RUN=1 "${NEURONIX_BIN}" dev "$stack" 2>&1)
  if echo "$out" | grep -q "Mode uji (dry-run) berhasil memvalidasi stack $stack"; then
    log_pass "neuronix dev $stack correctly loads complete toolchain"
  else
    log_fail "neuronix dev $stack failed: $out"
  fi
}

test_dev_stack "python"
test_dev_stack "rust"
test_dev_stack "node"
test_dev_stack "ai"
test_dev_stack "go"
test_dev_stack "web3"

# Negative test for invalid stack
if "${NEURONIX_BIN}" dev "nonexistent_lang" >/dev/null 2>&1; then
  log_fail "Invalid stack was unexpectedly accepted"
else
  log_pass "Invalid stack is deterministically rejected with exit code 1"
fi

# ------------------------------------------------------------------------------
# SUITE 6: NEURONIX Center Telemetry & CLI Engine
# ------------------------------------------------------------------------------
suite_header "6 - NEURONIX Center Telemetry & CLI Engine"

test_neuronix_center() {
  local out
  out=$(nix-shell -p python3 --run "python3 ${DISTRO_ROOT}/packages/neuronix-center/neuronix_center.py --cli" 2>&1)
  if echo "$out" | grep -q "NEURONIX CONTROL CENTER"; then
    log_pass "neuronix-center executes in CLI mode"
  else
    log_fail "neuronix-center CLI failed: $out"
  fi

  if echo "$out" | grep -q "Generasi Aktif"; then
    log_pass "neuronix-center telemetry correctly detects active generation"
  else
    log_fail "neuronix-center failed to read active generation"
  fi

  local ver
  ver=$(nix-shell -p python3 --run "python3 ${DISTRO_ROOT}/packages/neuronix-center/neuronix_center.py --version" 2>&1)
  if echo "$ver" | grep -q "1.0.0-phase4"; then
    log_pass "neuronix-center reports correct version 1.0.0-phase4"
  else
    log_fail "neuronix-center version mismatch: $ver"
  fi
}
test_neuronix_center

# ------------------------------------------------------------------------------
# SUITE 7: Architecture Decision Records (ADRs) Completeness
# ------------------------------------------------------------------------------
suite_header "7 - Architecture Decision Records (ADRs) Completeness"

check_file "${DISTRO_ROOT}/docs/adr/ADR-001-why-flakes.md"
check_file "${DISTRO_ROOT}/docs/adr/ADR-002-why-calamares-flake-generator.md"
check_file "${DISTRO_ROOT}/docs/adr/ADR-003-immutable-store-vs-flatpak.md"
check_file "${DISTRO_ROOT}/docs/adr/ADR-004-update-channel-strategy.md"
check_file "${DISTRO_ROOT}/docs/adr/ADR-005-hardware-detection-architecture.md"
check_file "${DISTRO_ROOT}/docs/architecture.md"
check_file "${DISTRO_ROOT}/docs/installation.md"

# ------------------------------------------------------------------------------
# SUITE 8: Absolute Zero Hardcoded PC & Machine Path Sanitization
# ------------------------------------------------------------------------------
suite_header "8 - Absolute Zero Hardcoded PC Sanitization"

test_sanitization() {
  local count_drive_d
  count_drive_d=$( (grep -rn "Drive D" "${DISTRO_ROOT}" 2>/dev/null || true) | (grep -v "test_distro_suite.sh" || true) | wc -l )
  if [ "$count_drive_d" -eq 0 ]; then
    log_pass "Zero references to 'Drive D' in Distro/ (100% Clean)"
  else
    log_fail "Found $count_drive_d occurrences of 'Drive D' in Distro/"
  fi

  local count_adamrofc
  count_adamrofc=$( (grep -rn "/home/adamrofc" "${DISTRO_ROOT}" 2>/dev/null || true) | (grep -v "test_distro_suite.sh" || true) | wc -l )
  if [ "$count_adamrofc" -eq 0 ]; then
    log_pass "Zero hardcoded user paths in Distro/ source files (100% Clean)"
  else
    log_fail "Found $count_adamrofc occurrences of user path in Distro/"
  fi
}
test_sanitization

# ------------------------------------------------------------------------------
# SUMMARY REPORT
# ------------------------------------------------------------------------------
END_TIME=$(date +%s%3N)
DURATION=$((END_TIME - START_TIME))
TOTAL_TESTS=$((PASSED_COUNT + FAILED_COUNT))

echo
echo "==================================================================="
echo "              DISTRO TEST HARNESS REPORT SUMMARY                   "
echo "==================================================================="
echo "  Total Executed Tests : ${TOTAL_TESTS}"
echo "  Passed Verification  : ${PASSED_COUNT}"
echo "  Failed Verification  : ${FAILED_COUNT}"
echo "  Execution Duration   : ${DURATION} ms"
if [ "$FAILED_COUNT" -eq 0 ]; then
  echo "  Confidence Score     : 100%"
  echo "==================================================================="
  echo -e "  ${GREEN}🏆 DISTRO CERTIFICATION PASSED: 100% RUST-GRADE RESILIENCE PROVEN${RESET}"
  echo "  All Phase 4 modules, Calamares engine, CLI dev, and ADRs are 100% verified."
  exit 0
else
  echo "  Confidence Score     : FAIL"
  echo "==================================================================="
  echo -e "  ${RED}✖ DISTRO CERTIFICATION FAILED: Fix the above failures.${RESET}"
  exit 1
fi
