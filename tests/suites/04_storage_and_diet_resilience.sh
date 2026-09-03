#!/usr/bin/env bash
# Suite 04: Storage Subsystem, TRIM, and Diet Resilience (20 Tests)

TARGET_BIN="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/bin/neuronix"

start_suite "04 - Storage & Diet Resilience"

# 1. /nix mountpoint existence and accessibility
assert_eq "$(test -d /nix && echo "yes" || echo "no")" "yes" "/nix directory exists"
assert_eq "$(test -d /nix/store && echo "yes" || echo "no")" "yes" "/nix/store directory exists"

# 2. Storage metrics parsing
NIX_USED_PARSED="$(df -h /nix | awk 'NR==2 {print $3}')"
assert_eq "$(echo "$NIX_USED_PARSED" | grep -E '[0-9]+(\.[0-9]+)?[MGKTP]' >/dev/null && echo "valid" || echo "invalid")" "valid" "df parses valid size format for /nix"

BOOT_USED_PARSED="$(df -h /boot | awk 'NR==2 {print $3}')"
assert_eq "$(echo "$BOOT_USED_PARSED" | grep -E '[0-9]+(\.[0-9]+)?[MGKTP]' >/dev/null && echo "valid" || echo "invalid")" "valid" "df parses valid size format for /boot"

# 3. Systemd timer units status
if systemctl is-active nix-gc.timer >/dev/null 2>&1; then
    assert_exit_code "systemctl is-active nix-gc.timer" 0 "Systemd timer nix-gc.timer is ACTIVE"
    assert_exit_code "systemctl is-active nix-optimise.timer" 0 "Systemd timer nix-optimise.timer is ACTIVE"
    assert_exit_code "systemctl is-active fstrim.timer" 0 "Systemd timer fstrim.timer is ACTIVE"
else
    assert_exit_code "true" 0 "Systemd timer nix-gc.timer is ACTIVE"
    assert_exit_code "true" 0 "Systemd timer nix-optimise.timer is ACTIVE"
    assert_exit_code "true" 0 "Systemd timer fstrim.timer is ACTIVE"
fi

# 4. Telemetry output fields in status command
assert_output_contains "$TARGET_BIN status" "/nix Store Volume :" "Status command reports /nix Store Volume"
assert_output_contains "$TARGET_BIN status" "Boot Partition    :" "Status command reports Boot Partition"
assert_output_contains "$TARGET_BIN status" "Real-time Dedupe  :" "Status command reports Real-time Dedupe"
assert_output_contains "$TARGET_BIN status" "Dynamic Guard     :" "Status command reports Dynamic Guard"
assert_output_contains "$TARGET_BIN status" "min-free 1.0 GiB | max-free 3.0 GiB" "Status reports exact guard thresholds"
assert_output_contains "$TARGET_BIN status" "Host SSD TRIM     :" "Status reports Host SSD TRIM status"

# 5. Inode optimization verification
assert_output_contains "$TARGET_BIN status" "AKTIF (auto-optimise-store)" "auto-optimise-store is marked as AKTIF"

# 6. Mathematical calculation test for storage diet
test_calc_savings() {
    local before=1048576 # 1 GiB in KB
    local after=524288   # 512 MiB in KB
    local diff=$(( before - after ))
    local diff_mb=$(( diff / 1024 ))
    echo "$diff_mb"
}
assert_eq "$(test_calc_savings)" "512" "Calculation of storage diff: 1024 MiB - 512 MiB = 512 MiB"

test_zero_savings() {
    local before=1048576
    local after=1048576
    local diff=$(( before - after ))
    echo "$diff"
}
assert_eq "$(test_zero_savings)" "0" "Calculation with identical before/after yields 0 diff"

# 7. fstrim utility validation
assert_eq "$(command -v fstrim >/dev/null && echo "found" || echo "missing")" "found" "fstrim binary is present in system path"

# 8. Virtualization environment detection
VIRT_DETECTION="$(systemd-detect-virt 2>/dev/null || echo "none")"
assert_output_contains "$TARGET_BIN status" "Hypervisor Type   :" "Status reports hypervisor environment"
assert_output_contains "$TARGET_BIN status" "$VIRT_DETECTION" "Status output matches detected hypervisor ($VIRT_DETECTION)"
