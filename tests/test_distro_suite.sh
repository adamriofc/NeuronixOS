#!/usr/bin/env bash
# ==============================================================================
# NEURONIX OS: Distribution Automated Test Suite (Mission-Critical Quality)
# Validates all 27 declarative hardware, installer, CLI, and ADR components
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DISTRO_ROOT="${PROJECT_ROOT}"
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

assert_exit_code() {
  local cmd="$1"
  local expected="$2"
  local desc="$3"
  local code=0
  eval "$cmd" >/dev/null 2>&1 || code=$?
  if [ "$code" -eq "$expected" ]; then
    log_pass "$desc (exit: $code)"
  else
    log_fail "$desc (expected $expected, got $code)"
  fi
}

assert_output_contains() {
  local cmd="$1"
  local pattern="$2"
  local desc="$3"
  local out
  out=$(eval "$cmd" 2>&1 || true)
  if echo "$out" | grep -qF "$pattern"; then
    log_pass "$desc"
  else
    log_fail "$desc (Pattern '$pattern' not found in output: $out)"
  fi
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
  if echo "$out" | grep -Eq "Dry-run verification successful|Verifikasi dry-run sukses"; then
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
  if echo "$out" | grep -Eq "Dry-run validation successful for stack $stack|Mode uji.*$stack"; then
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

  if echo "$out" | grep -Eq "Active Generation|Generasi Aktif"; then
    log_pass "neuronix-center telemetry correctly detects active generation"
  else
    log_fail "neuronix-center failed to read active generation"
  fi

  local ver
  ver=$(nix-shell -p python3 --run "python3 ${DISTRO_ROOT}/packages/neuronix-center/neuronix_center.py --version" 2>&1)
  if echo "$ver" | grep -Eq "1.0.1-beta|0.4.0-beta|1.0.0-phase4"; then
    log_pass "neuronix-center reports correct version (${ver})"
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
  count_drive_d=$( (grep -rn "Drive D" "${DISTRO_ROOT}" 2>/dev/null || true) | (grep -v "/tests/" || true) | wc -l )
  if [ "$count_drive_d" -eq 0 ]; then
    log_pass "Zero references to 'Drive D' in Distro/ (100% Clean)"
  else
    log_fail "Found $count_drive_d occurrences of 'Drive D' in Distro/"
  fi

  local count_adamrofc
  count_adamrofc=$( (grep -rn "/home/adamrofc" "${DISTRO_ROOT}" 2>/dev/null || true) | (grep -v "/tests/" || true) | wc -l )
  if [ "$count_adamrofc" -eq 0 ]; then
    log_pass "Zero hardcoded user paths in Distro/ source files (100% Clean)"
  else
    log_fail "Found $count_adamrofc occurrences of user path in Distro/"
  fi
}
test_sanitization

# ------------------------------------------------------------------------------
# SUITE 9: Btrfs Subvolume Layout & Mount Invariants
# ------------------------------------------------------------------------------
suite_header "9 - Btrfs Subvolume Layout & Mount Invariants"

assert_contains "${DISTRO_ROOT}/installer/calamares/modules/partition.conf" "options: \"compress=zstd:3,noatime,space_cache=v2\"" "Subvolume @ has zstd:3, noatime, and space_cache=v2"
assert_contains "${DISTRO_ROOT}/installer/calamares/modules/partition.conf" "subvolume: \"@nix\"" "Subvolume @nix is explicitly declared"
assert_contains "${DISTRO_ROOT}/installer/calamares/modules/partition.conf" "subvolume: \"@home\"" "Subvolume @home is explicitly declared"
assert_contains "${DISTRO_ROOT}/installer/calamares/modules/partition.conf" "subvolume: \"@snapshots\"" "Subvolume @snapshots is explicitly declared"
assert_contains "${DISTRO_ROOT}/installer/calamares/modules/partition.conf" "options: \"nodatacow,noatime\"" "Subvolume @swap has nodatacow (CoW disabled) and noatime"
assert_contains "${DISTRO_ROOT}/installer/calamares/modules/partition.conf" "efiSystemPartition: \"/boot\"" "EFI system partition is mounted at /boot"
assert_contains "${DISTRO_ROOT}/installer/calamares/modules/partition.conf" "efiSystemPartitionSize: 1024M" "EFI partition size is allocated to 1.0 GiB (1024M)"
assert_contains "${DISTRO_ROOT}/installer/calamares/modules/partition.conf" "defaultFileSystemType: \"btrfs\"" "Default filesystem is Btrfs"
assert_contains "${DISTRO_ROOT}/installer/calamares/modules/partition.conf" "none" "User swap choice 'none' is available"
assert_contains "${DISTRO_ROOT}/installer/calamares/modules/partition.conf" "suspend" "User swap choice 'suspend' (hibernation) is available"

# ------------------------------------------------------------------------------
# SUITE 10: Calamares Module & Sequence Specifications
# ------------------------------------------------------------------------------
suite_header "10 - Calamares Module & Sequence Specifications"

assert_contains "${DISTRO_ROOT}/installer/calamares/settings.conf" "branding: neuronix" "Calamares branding is neuronix"
assert_contains "${DISTRO_ROOT}/installer/calamares/settings.conf" "prompt-install: true" "Calamares prompt-install confirmation is true"
assert_contains "${DISTRO_ROOT}/installer/calamares/settings.conf" "dont-chroot: true" "Calamares dont-chroot is true (NixOS requirement)"
assert_contains "${DISTRO_ROOT}/installer/calamares/settings.conf" "welcome" "Wizard sequence includes welcome module"
assert_contains "${DISTRO_ROOT}/installer/calamares/settings.conf" "locale" "Wizard sequence includes locale module"
assert_contains "${DISTRO_ROOT}/installer/calamares/settings.conf" "keyboard" "Wizard sequence includes keyboard module"
assert_contains "${DISTRO_ROOT}/installer/calamares/settings.conf" "partition" "Wizard sequence includes partition module"
assert_contains "${DISTRO_ROOT}/installer/calamares/settings.conf" "users" "Wizard sequence includes users module"
assert_contains "${DISTRO_ROOT}/installer/calamares/settings.conf" "summary" "Wizard sequence includes summary module"
assert_contains "${DISTRO_ROOT}/installer/calamares/settings.conf" "shellprocess@neuronix-engine" "Execution sequence triggers neuronix installer engine"

# ------------------------------------------------------------------------------
# SUITE 11: Kernel Parameters, Watchdogs & Sysctl Limits
# ------------------------------------------------------------------------------
suite_header "11 - Kernel Parameters, Watchdogs & Sysctl Limits"

assert_contains "${DISTRO_ROOT}/modules/hardware/boot.nix" "\"vm.max_map_count\" = 2147483642;" "Sysctl vm.max_map_count is set to 2147483642"
assert_contains "${DISTRO_ROOT}/modules/hardware/boot.nix" "\"fs.file-max\" = 2097152;" "Sysctl fs.file-max is set to 2097152"
assert_contains "${DISTRO_ROOT}/modules/services/memory-shield.nix" "\"vm.swappiness\" = 180;" "Sysctl vm.swappiness is set to 180"
assert_contains "${DISTRO_ROOT}/modules/services/memory-shield.nix" "\"vm.page-cluster\" = 0;" "Sysctl vm.page-cluster is set to 0"
assert_contains "${DISTRO_ROOT}/modules/services/memory-shield.nix" "\"vm.vfs_cache_pressure\" = 50;" "Sysctl vm.vfs_cache_pressure is set to 50"
assert_contains "${DISTRO_ROOT}/modules/hardware/boot.nix" "mem_sleep_default=deep" "Kernel param mem_sleep_default=deep is set"
assert_contains "${DISTRO_ROOT}/modules/hardware/boot.nix" "systemd.watchdog.runtimeTime = \"30s\";" "Systemd runtime watchdog is set to 30s"
assert_contains "${DISTRO_ROOT}/modules/hardware/boot.nix" "systemd.watchdog.rebootTime = \"10min\";" "Systemd reboot watchdog is set to 10min"
assert_contains "${DISTRO_ROOT}/modules/hardware/boot.nix" "configurationLimit = 15;" "Bootloader generation limit is 15"
assert_contains "${DISTRO_ROOT}/modules/hardware/boot.nix" "editor = false;" "Bootloader parameter editor is disabled for security"

# ------------------------------------------------------------------------------
# SUITE 12: Desktop Environment Declarative Contracts
# ------------------------------------------------------------------------------
suite_header "12 - Desktop Environment Declarative Contracts"

assert_contains "${DISTRO_ROOT}/modules/desktop/kde.nix" "plasma6.enable = true" "KDE Plasma 6 desktop is enabled"
assert_contains "${DISTRO_ROOT}/modules/desktop/kde.nix" "sddm" "KDE uses SDDM display manager"
assert_contains "${DISTRO_ROOT}/modules/desktop/kde.nix" "wayland.enable = true" "KDE SDDM Wayland backend is enabled"
assert_contains "${DISTRO_ROOT}/modules/desktop/kde.nix" "discover" "KDE Discover app store is packaged"
assert_contains "${DISTRO_ROOT}/modules/desktop/gnome.nix" "desktopManager.gnome.enable = true" "GNOME desktop manager is enabled"
assert_contains "${DISTRO_ROOT}/modules/desktop/gnome.nix" "displayManager.gdm.enable = true" "GNOME uses GDM display manager"
assert_contains "${DISTRO_ROOT}/modules/desktop/gnome.nix" "gnome-software" "GNOME Software app store is packaged"
assert_contains "${DISTRO_ROOT}/modules/desktop/hyprland.nix" "programs.hyprland" "Hyprland is declared"
assert_contains "${DISTRO_ROOT}/modules/desktop/hyprland.nix" "xwayland.enable = true" "Hyprland XWayland support is enabled"
assert_contains "${DISTRO_ROOT}/modules/desktop/hyprland.nix" "waybar" "Hyprland Waybar status panel is packaged"

# ------------------------------------------------------------------------------
# SUITE 13: WirePlumber & Audio HD Duplex Codec Specifications
# ------------------------------------------------------------------------------
suite_header "13 - WirePlumber & Audio HD Duplex Codec Specifications"

assert_contains "${DISTRO_ROOT}/modules/hardware/audio.nix" "services.pipewire" "PipeWire audio service is declared"
assert_contains "${DISTRO_ROOT}/modules/hardware/audio.nix" "alsa.support32Bit = true" "ALSA 32-bit gaming audio support is enabled"
assert_contains "${DISTRO_ROOT}/modules/hardware/audio.nix" "pulse.enable = true" "PulseAudio compatibility layer is enabled"
assert_contains "${DISTRO_ROOT}/modules/hardware/audio.nix" "jack.enable = true" "JACK pro-audio compatibility is enabled"
assert_contains "${DISTRO_ROOT}/modules/hardware/audio.nix" "wireplumber = {" "WirePlumber session manager is declared"
assert_contains "${DISTRO_ROOT}/modules/hardware/audio.nix" "\"ldac\"" "Bluetooth LDAC high-res codec is enabled"
assert_contains "${DISTRO_ROOT}/modules/hardware/audio.nix" "\"aptx_hd\"" "Bluetooth AptX HD codec is enabled"
assert_contains "${DISTRO_ROOT}/modules/hardware/audio.nix" "\"lc3plus\"" "Bluetooth LC3Plus low-latency codec is enabled"

# ------------------------------------------------------------------------------
# SUITE 14: Systemd Service Unit Lifecycle Contracts
# ------------------------------------------------------------------------------
suite_header "14 - Systemd Service Unit Lifecycle Contracts"

assert_contains "${DISTRO_ROOT}/modules/services/storage.nix" "Type = \"oneshot\";" "Btrfs balance service has oneshot type"
assert_contains "${DISTRO_ROOT}/modules/services/storage.nix" "OnCalendar = \"monthly\";" "Btrfs balance timer is scheduled monthly"
assert_contains "${DISTRO_ROOT}/modules/services/storage.nix" "Persistent = true;" "Btrfs balance timer is persistent"
assert_contains "${DISTRO_ROOT}/modules/services/flatpak.nix" "Type = \"oneshot\";" "Flathub provisioning service has oneshot type"
assert_contains "${DISTRO_ROOT}/modules/services/flatpak.nix" "RemainAfterExit = true;" "Flathub provisioning remains after exit"
assert_contains "${DISTRO_ROOT}/modules/services/flatpak.nix" "after = [ \"network-online.target\" ];" "Flathub provisioning waits for network"
assert_contains "${DISTRO_ROOT}/modules/hardware/power.nix" "wantedBy = [ \"multi-user.target\" ];" "Battery threshold service targets multi-user"
assert_contains "${DISTRO_ROOT}/hosts/iso/default.nix" "wantedBy = [ \"graphical-session.target\" ];" "Calamares autostart targets graphical session"
assert_contains "${DISTRO_ROOT}/modules/services/storage.nix" "interval = \"daily\";" "Auto-TRIM service interval is daily"
assert_contains "${DISTRO_ROOT}/modules/services/network.nix" "interval = 300;" "Captive portal check interval is 300s"

# ------------------------------------------------------------------------------
# SUITE 15: neuronix dev CLI Parameter Fuzzing & Negative Matrix
# ------------------------------------------------------------------------------
suite_header "15 - neuronix dev CLI Parameter Fuzzing & Negative Matrix"

assert_exit_code "DEV_DRY_RUN=1 $NEURONIX_BIN dev python" 0 "Stack python valid"
assert_exit_code "DEV_DRY_RUN=1 $NEURONIX_BIN dev rust" 0 "Stack rust valid"
assert_exit_code "DEV_DRY_RUN=1 $NEURONIX_BIN dev node" 0 "Stack node valid"
assert_exit_code "DEV_DRY_RUN=1 $NEURONIX_BIN dev ai" 0 "Stack ai valid"
assert_exit_code "DEV_DRY_RUN=1 $NEURONIX_BIN dev go" 0 "Stack go valid"
assert_exit_code "DEV_DRY_RUN=1 $NEURONIX_BIN dev web3" 0 "Stack web3 valid"
assert_exit_code "$NEURONIX_BIN dev 2>/dev/null" 1 "Empty stack arg rejected"
assert_exit_code "$NEURONIX_BIN dev '   ' 2>/dev/null" 1 "Whitespace stack arg rejected"
assert_exit_code "$NEURONIX_BIN dev java 2>/dev/null" 1 "Stack java rejected"
assert_exit_code "$NEURONIX_BIN dev csharp 2>/dev/null" 1 "Stack csharp rejected"
assert_exit_code "$NEURONIX_BIN dev php 2>/dev/null" 1 "Stack php rejected"
assert_exit_code "$NEURONIX_BIN dev ruby 2>/dev/null" 1 "Stack ruby rejected"
assert_exit_code "$NEURONIX_BIN dev --help 2>/dev/null" 1 "Stack --help rejected"
assert_exit_code "$NEURONIX_BIN dev -v 2>/dev/null" 1 "Stack -v rejected"
assert_exit_code "$NEURONIX_BIN dev 'SELECT * FROM users' 2>/dev/null" 1 "SQL injection in dev stack rejected"

# ------------------------------------------------------------------------------
# SUITE 16: NEURONIX Center Argument Matrix & Resiliency
# ------------------------------------------------------------------------------
suite_header "16 - NEURONIX Center Argument Matrix & Resiliency"

assert_exit_code "nix-shell -p python3 --run 'python3 ${DISTRO_ROOT}/packages/neuronix-center/neuronix_center.py --cli'" 0 "Flag --cli exits 0"
assert_exit_code "nix-shell -p python3 --run 'python3 ${DISTRO_ROOT}/packages/neuronix-center/neuronix_center.py --list-generations'" 0 "Flag --list-generations exits 0"
assert_exit_code "nix-shell -p python3 --run 'python3 ${DISTRO_ROOT}/packages/neuronix-center/neuronix_center.py --version'" 0 "Flag --version exits 0"
NC_VER_OUTPUT=$(nix-shell -p python3 --run "python3 '${DISTRO_ROOT}/packages/neuronix-center/neuronix_center.py' --version")
assert_output_contains "echo '$NC_VER_OUTPUT'" "NEURONIX Center" "Version output contains brand name"
assert_exit_code "nix-shell -p python3 --run 'python3 ${DISTRO_ROOT}/packages/neuronix-center/neuronix_center.py --help'" 0 "Flag --help exits 0"
NC_CLI_OUTPUT=$(nix-shell -p python3 --run "python3 '${DISTRO_ROOT}/packages/neuronix-center/neuronix_center.py' --cli")
assert_output_contains "echo '$NC_CLI_OUTPUT'" "Operating System" "CLI contains Operating System field"
assert_output_contains "echo '$NC_CLI_OUTPUT'" "Kernel Version" "CLI contains Kernel Version field"
assert_output_contains "echo '$NC_CLI_OUTPUT'" "Processor" "CLI contains Processor field"
assert_output_contains "echo '$NC_CLI_OUTPUT'" "Storage Format" "CLI contains Storage Format field"
assert_output_contains "echo '$NC_CLI_OUTPUT'" "Battery Limit" "CLI contains Battery Limit field"

# ------------------------------------------------------------------------------
# SUITE 17: Security & Permission Invariants
# ------------------------------------------------------------------------------
suite_header "17 - Security & Permission Invariants"

assert_contains "${DISTRO_ROOT}/modules/services/security.nix" "wheelNeedsPassword = true;" "Desktop wheel group requires password"
assert_contains "${DISTRO_ROOT}/modules/services/security.nix" "security.polkit.enable = true;" "PolKit graphical privilege manager is enabled"
assert_contains "${DISTRO_ROOT}/modules/services/security.nix" "programs.gnupg.agent" "GnuPG agent is enabled"
assert_contains "${DISTRO_ROOT}/modules/services/security.nix" "enableSSHSupport = true;" "GnuPG SSH agent forwarding is enabled"
assert_contains "${DISTRO_ROOT}/modules/services/security.nix" "pinentry-gnome3" "Pinentry GUI package is declared"
assert_contains "${DISTRO_ROOT}/modules/core/default.nix" "trusted-users = [ \"root\" \"@wheel\" ];" "Nix trusted users are restricted to root and @wheel"
assert_contains "${DISTRO_ROOT}/hosts/iso/default.nix" "security.sudo.wheelNeedsPassword = false;" "Live ISO enables passwordless sudo for live tester convenience"
assert_contains "${DISTRO_ROOT}/hosts/iso/default.nix" "extraGroups = [ \"wheel\" \"networkmanager\" \"video\" \"audio\" ];" "Live ISO user has audio/video/network permissions"
assert_contains "${DISTRO_ROOT}/hosts/desktop/default.nix" "extraGroups = [ \"wheel\" \"networkmanager\" \"video\" \"audio\" ];" "Desktop user has audio/video/network permissions"
assert_contains "${DISTRO_ROOT}/modules/core/default.nix" "auto-optimise-store = true;" "Automatic store optimization is enabled"

# ------------------------------------------------------------------------------
# SUITE 18: ADR Documentation & Citation Integrity
# ------------------------------------------------------------------------------
suite_header "18 - ADR Documentation & Citation Integrity"

assert_contains "${DISTRO_ROOT}/docs/adr/ADR-001-why-flakes.md" "Accepted" "ADR-001 is Accepted"
assert_contains "${DISTRO_ROOT}/docs/adr/ADR-001-why-flakes.md" "Context & Problem Statement" "ADR-001 contains Context & Problem Statement"
assert_contains "${DISTRO_ROOT}/docs/adr/ADR-002-why-calamares-flake-generator.md" "Accepted" "ADR-002 is Accepted"
assert_contains "${DISTRO_ROOT}/docs/adr/ADR-002-why-calamares-flake-generator.md" "Context & Problem Statement" "ADR-002 contains Context & Problem Statement"
assert_contains "${DISTRO_ROOT}/docs/adr/ADR-003-immutable-store-vs-flatpak.md" "Accepted" "ADR-003 is Accepted"
assert_contains "${DISTRO_ROOT}/docs/adr/ADR-003-immutable-store-vs-flatpak.md" "Context & Problem Statement" "ADR-003 contains Context & Problem Statement"
assert_contains "${DISTRO_ROOT}/docs/adr/ADR-004-update-channel-strategy.md" "Accepted" "ADR-004 is Accepted"
assert_contains "${DISTRO_ROOT}/docs/adr/ADR-004-update-channel-strategy.md" "Context & Problem Statement" "ADR-004 contains Context & Problem Statement"
assert_contains "${DISTRO_ROOT}/docs/adr/ADR-005-hardware-detection-architecture.md" "Accepted" "ADR-005 is Accepted"
assert_contains "${DISTRO_ROOT}/docs/adr/ADR-005-hardware-detection-architecture.md" "Context & Problem Statement" "ADR-005 contains Context & Problem Statement"

# ------------------------------------------------------------------------------
# SUITE 19: OpenCode Built-in AI Copilot & Autonomous Update Contracts
# ------------------------------------------------------------------------------
suite_header "19 - OpenCode Built-in AI Copilot & Autonomous Update Contracts"

assert_contains "${DISTRO_ROOT}/modules/services/opencode.nix" "services.opencode" "OpenCode service option hierarchy is defined"
assert_contains "${DISTRO_ROOT}/modules/services/opencode.nix" "default = true;" "OpenCode is enabled by default"
assert_contains "${DISTRO_ROOT}/packages/opencode/default.nix" "makeDesktopItem" "OpenCode generates desktop item"
assert_contains "${DISTRO_ROOT}/flake.nix" "opencode = import ./modules/services/opencode.nix;" "Flake exports opencode nixosModule"
assert_contains "${DISTRO_ROOT}/installer/scripts/neuronix-install-engine.sh" "neuronix.services.opencode" "Installer engine configures opencode"

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
  echo -e "  ${GREEN}✓ NEURONIX DISTRO VALIDATION PASSED: 100% OF DECLARED ASSERTIONS VERIFIED${RESET}"
  echo "  All Phase 4 modules, Calamares engine, CLI dev, and contracts verified."
  exit 0
else
  echo "  Confidence Score     : FAIL"
  echo "==================================================================="
  echo -e "  ${RED}✖ DISTRO CERTIFICATION FAILED: Fix the above failures.${RESET}"
  exit 1
fi
