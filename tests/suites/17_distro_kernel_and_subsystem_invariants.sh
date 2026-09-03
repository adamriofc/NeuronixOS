#!/usr/bin/env bash
# ==============================================================================
# Suite 17: Distro Kernel, Memory & Subsystem Invariants (35 Tests)
# Validates system sysctl limits, watchdog timings, S0ix parameters, PipeWire HD
# ==============================================================================

DISTRO_PATH="${PROJECT_ROOT}/Distro"

start_suite "17 - Distro Kernel, Memory & Subsystem Invariants"

# 1-5. Sysctl Value Range & Bounds
assert_output_contains "grep -F '\"vm.max_map_count\" = 2147483642;' '${DISTRO_PATH}/modules/hardware/boot.nix'" "2147483642" "vm.max_map_count matches SteamOS 2.14B value"
assert_output_contains "grep -F '\"fs.file-max\" = 2097152;' '${DISTRO_PATH}/modules/hardware/boot.nix'" "2097152" "fs.file-max matches 2M open file descriptors"
assert_output_contains "grep -F '\"vm.swappiness\" = 180;' '${DISTRO_PATH}/modules/services/memory-shield.nix'" "180" "vm.swappiness is aggressively tuned to 180 for ZRAM"
assert_output_contains "grep -F '\"vm.page-cluster\" = 0;' '${DISTRO_PATH}/modules/services/memory-shield.nix'" "0" "vm.page-cluster is 0 for zero readahead latency in RAM"
assert_output_contains "grep -F '\"vm.vfs_cache_pressure\" = 50;' '${DISTRO_PATH}/modules/services/memory-shield.nix'" "50" "vm.vfs_cache_pressure retains dentries/inodes"

# 6-10. Kernel Parameters & Power Management
assert_output_contains "grep -F 'mem_sleep_default=deep' '${DISTRO_PATH}/modules/hardware/boot.nix'" "mem_sleep_default=deep" "S0ix sleep parameter is declared"
assert_output_contains "grep -F 'snd_hda_intel power_save=0' '${DISTRO_PATH}/modules/hardware/audio.nix'" "power_save=0" "ALSA powersave 0 prevents audio popping"
assert_output_contains "grep -F 'services.power-profiles-daemon.enable' '${DISTRO_PATH}/modules/hardware/power.nix'" "power-profiles-daemon" "power-profiles-daemon is active"
assert_output_contains "grep -F 'services.thermald.enable' '${DISTRO_PATH}/modules/hardware/power.nix'" "thermald" "Intel/AMD thermald prevention is active"
assert_output_contains "grep -F 'charge_control_limit_max' '${DISTRO_PATH}/modules/hardware/power.nix'" "charge_control_limit_max" "80% battery longevity limit is declared"

# 11-15. UEFI Bootloader & Watchdogs
assert_output_contains "grep -F 'systemd.watchdog.runtimeTime = \"30s\";' '${DISTRO_PATH}/modules/hardware/boot.nix'" "30s" "Runtime watchdog is 30s"
assert_output_contains "grep -F 'systemd.watchdog.rebootTime = \"10min\";' '${DISTRO_PATH}/modules/hardware/boot.nix'" "10min" "Reboot watchdog is 10min"
assert_output_contains "grep -F 'configurationLimit = 15;' '${DISTRO_PATH}/modules/hardware/boot.nix'" "15" "Bootloader generation limit is 15"
assert_output_contains "grep -F 'editor = false;' '${DISTRO_PATH}/modules/hardware/boot.nix'" "editor = false" "Kernel parameter editor is disabled"
assert_output_contains "grep -F 'canTouchEfiVariables = true;' '${DISTRO_PATH}/modules/hardware/boot.nix'" "canTouchEfiVariables" "EFI variables access is enabled"

# 16-20. Active Memory Pressure Shield (PSI & ZRAM)
assert_output_contains "grep -F 'zramSwap = {' '${DISTRO_PATH}/modules/services/memory-shield.nix'" "zramSwap" "ZRAM Swap is enabled"
assert_output_contains "grep -F 'algorithm = \"zstd\";' '${DISTRO_PATH}/modules/services/memory-shield.nix'" "zstd" "ZRAM compression uses ZSTD"
assert_output_contains "grep -F 'memoryPercent = 100;' '${DISTRO_PATH}/modules/services/memory-shield.nix'" "100" "ZRAM capacity is 100% of physical RAM"
assert_output_contains "grep -F 'systemd.oomd = {' '${DISTRO_PATH}/modules/services/memory-shield.nix'" "systemd.oomd" "systemd-oomd is active"
assert_output_contains "grep -F 'enableUserSlices = true;' '${DISTRO_PATH}/modules/services/memory-shield.nix'" "enableUserSlices" "systemd-oomd user slices are protected"

# 21-25. Audio PipeWire HD Duplex & Bluetooth Codecs
assert_output_contains "grep -F 'services.pipewire = {' '${DISTRO_PATH}/modules/hardware/audio.nix'" "services.pipewire" "PipeWire core is enabled"
assert_output_contains "grep -F 'alsa.support32Bit = true;' '${DISTRO_PATH}/modules/hardware/audio.nix'" "support32Bit" "ALSA 32-bit gaming audio is enabled"
assert_output_contains "grep -F 'pulse.enable = true;' '${DISTRO_PATH}/modules/hardware/audio.nix'" "pulse.enable" "PulseAudio compatibility is enabled"
assert_output_contains "grep -F 'jack.enable = true;' '${DISTRO_PATH}/modules/hardware/audio.nix'" "jack.enable" "JACK compatibility is enabled"
assert_output_contains "grep -F '\"ldac\"' '${DISTRO_PATH}/modules/hardware/audio.nix'" "ldac" "Bluetooth LDAC codec is declared"

# 26-30. High-Fidelity Audio Extra Codecs
assert_output_contains "grep -F '\"aptx_hd\"' '${DISTRO_PATH}/modules/hardware/audio.nix'" "aptx_hd" "Bluetooth AptX HD is declared"
assert_output_contains "grep -F '\"lc3plus\"' '${DISTRO_PATH}/modules/hardware/audio.nix'" "lc3plus" "Bluetooth LC3Plus is declared"
assert_output_contains "grep -F '\"aac\"' '${DISTRO_PATH}/modules/hardware/audio.nix'" "aac" "Bluetooth AAC is declared"
assert_output_contains "grep -F 'bluez5.enable-sbc-xq' '${DISTRO_PATH}/modules/hardware/audio.nix'" "sbc-xq" "Bluetooth SBC-XQ is declared"
assert_output_contains "grep -F 'wireplumber = {' '${DISTRO_PATH}/modules/hardware/audio.nix'" "wireplumber" "WirePlumber is configured"

# 31-35. Graphics, VA-API & CPU Microcode
assert_output_contains "grep -F 'hardware.graphics = {' '${DISTRO_PATH}/modules/hardware/nvidia-prime.nix'" "hardware.graphics" "Hardware graphics is enabled"
assert_output_contains "grep -F 'enable32Bit = true;' '${DISTRO_PATH}/modules/hardware/nvidia-prime.nix'" "enable32Bit" "32-bit graphics is enabled"
assert_output_contains "grep -F 'hardware.cpu.intel.updateMicrocode' '${DISTRO_PATH}/modules/hardware/cpu.nix'" "updateMicrocode" "Intel CPU microcode updates enabled"
assert_output_contains "grep -F 'hardware.cpu.amd.updateMicrocode' '${DISTRO_PATH}/modules/hardware/cpu.nix'" "updateMicrocode" "AMD CPU microcode updates enabled"
assert_output_contains "grep -F 'time.hardwareClockInLocalTime' '${DISTRO_PATH}/modules/hardware/boot.nix'" "hardwareClockInLocalTime" "Dual boot Windows RTC clock sync enabled"
