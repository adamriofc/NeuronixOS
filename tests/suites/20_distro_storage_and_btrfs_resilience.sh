#!/usr/bin/env bash
# ==============================================================================
# Suite 20: Distro Storage, Btrfs & Filesystem Resilience (35 Tests)
# Validates Btrfs subvolumes, nodatacow on @swap, auto-TRIM, and NTFS3
# ==============================================================================

DISTRO_PATH="${PROJECT_ROOT}/Distro"

start_suite "20 - Distro Storage, Btrfs & Filesystem Resilience"

# 1-7. Supported Filesystems & Auto-Mount Drivers
assert_output_contains "grep -F '\"btrfs\"' '${DISTRO_PATH}/modules/services/storage.nix'" "btrfs" "Btrfs kernel module supported"
assert_output_contains "grep -F '\"ntfs\"' '${DISTRO_PATH}/modules/services/storage.nix'" "ntfs" "NTFS kernel module supported"
assert_output_contains "grep -F '\"exfat\"' '${DISTRO_PATH}/modules/services/storage.nix'" "exfat" "exFAT kernel module supported"
assert_output_contains "grep -F '\"vfat\"' '${DISTRO_PATH}/modules/services/storage.nix'" "vfat" "VFAT kernel module supported"
assert_output_contains "grep -F 'services.fstrim' '${DISTRO_PATH}/modules/services/storage.nix'" "fstrim" "Periodic SSD TRIM is configured"
assert_output_contains "grep -F 'interval = \"daily\";' '${DISTRO_PATH}/modules/services/storage.nix'" "daily" "SSD TRIM runs on daily interval"
assert_output_contains "grep -F 'services.udisks2.enable = true;' '${DISTRO_PATH}/modules/services/storage.nix'" "udisks2" "UDisks2 removable auto-mount is enabled"

# 8-14. Btrfs Balance Maintenance Systemd Invariants
assert_output_contains "grep -F 'systemd.services.btrfs-balance' '${DISTRO_PATH}/modules/services/storage.nix'" "btrfs-balance" "btrfs-balance service is defined"
assert_output_contains "grep -F 'systemd.timers.btrfs-balance' '${DISTRO_PATH}/modules/services/storage.nix'" "btrfs-balance" "btrfs-balance timer is defined"
assert_output_contains "grep -F 'btrfs balance start' '${DISTRO_PATH}/modules/services/storage.nix'" "btrfs balance start" "Balance targets underallocated block groups"
assert_output_contains "grep -F 'OnCalendar = \"monthly\";' '${DISTRO_PATH}/modules/services/storage.nix'" "monthly" "Balance runs monthly"
assert_output_contains "grep -F 'Persistent = true;' '${DISTRO_PATH}/modules/services/storage.nix'" "Persistent" "Timer catches up after wake from sleep"
assert_output_contains "grep -F 'Type = \"oneshot\";' '${DISTRO_PATH}/modules/services/storage.nix'" "oneshot" "Balance service exits after one run"
assert_output_contains "grep -F 'wantedBy = [ \"timers.target\" ];' '${DISTRO_PATH}/modules/services/storage.nix'" "timers.target" "Timer binds to timers.target"

# 15-21. Calamares Subvolume Partitioning Invariants
assert_output_contains "grep -F 'subvolume: \"@\"' '${DISTRO_PATH}/installer/calamares/modules/partition.conf'" "subvolume: \"@\"" "Root subvolume @ defined"
assert_output_contains "grep -F 'mountPoint: \"/\"' '${DISTRO_PATH}/installer/calamares/modules/partition.conf'" "mountPoint: \"/\"" "Root subvolume mounts at /"
assert_output_contains "grep -F 'subvolume: \"@nix\"' '${DISTRO_PATH}/installer/calamares/modules/partition.conf'" "subvolume: \"@nix\"" "Nix store subvolume @nix defined"
assert_output_contains "grep -F 'mountPoint: \"/nix\"' '${DISTRO_PATH}/installer/calamares/modules/partition.conf'" "mountPoint: \"/nix\"" "Store subvolume mounts at /nix"
assert_output_contains "grep -F 'subvolume: \"@home\"' '${DISTRO_PATH}/installer/calamares/modules/partition.conf'" "subvolume: \"@home\"" "User home subvolume @home defined"
assert_output_contains "grep -F 'mountPoint: \"/home\"' '${DISTRO_PATH}/installer/calamares/modules/partition.conf'" "mountPoint: \"/home\"" "User home subvolume mounts at /home"
assert_output_contains "grep -F 'subvolume: \"@snapshots\"' '${DISTRO_PATH}/installer/calamares/modules/partition.conf'" "subvolume: \"@snapshots\"" "Snapshots subvolume defined"

# 22-28. Critical Anti-Corruption @swap Subvolume Invariants
assert_output_contains "grep -F 'subvolume: \"@swap\"' '${DISTRO_PATH}/installer/calamares/modules/partition.conf'" "subvolume: \"@swap\"" "Dedicated @swap subvolume defined"
assert_output_contains "grep -F 'mountPoint: \"/swap\"' '${DISTRO_PATH}/installer/calamares/modules/partition.conf'" "mountPoint: \"/swap\"" "@swap mounts at /swap"
assert_output_contains "grep -F 'nodatacow' '${DISTRO_PATH}/installer/calamares/modules/partition.conf'" "nodatacow" "nodatacow disables Copy-on-Write for swapfile"
assert_output_contains "grep -F 'noatime' '${DISTRO_PATH}/installer/calamares/modules/partition.conf'" "noatime" "noatime disables access time metadata writes"
assert_output_contains "grep -F 'efiSystemPartition: \"/boot\"' '${DISTRO_PATH}/installer/calamares/modules/partition.conf'" "/boot" "ESP mounted to /boot"
assert_output_contains "grep -F 'efiSystemPartitionSize: 1024M' '${DISTRO_PATH}/installer/calamares/modules/partition.conf'" "1024M" "ESP size is 1024M (prevents out-of-space)"
assert_output_contains "grep -F 'defaultFileSystemType: \"btrfs\"' '${DISTRO_PATH}/installer/calamares/modules/partition.conf'" "btrfs" "Default filesystem is Btrfs"

# 29-35. Storage Engine Mock Verification & Boundary Safety
MOCK_CONFIG="/tmp/neuronix-mock-install/etc/nixos/configuration.nix"
assert_eq "$(test -f "$MOCK_CONFIG" && echo "present" || echo "absent")" "present" "Mock installer created configuration.nix"
assert_output_contains "grep -F 'networking.networkmanager.enable = true;' '$MOCK_CONFIG'" "networkmanager" "Generated config enables NetworkManager"
assert_output_contains "grep -F 'programs.nix-ld.enable = true;' '$MOCK_CONFIG'" "nix-ld" "Generated config enables nix-ld global loader"
assert_output_contains "grep -F 'nix.settings.experimental-features' '$MOCK_CONFIG'" "experimental-features" "Generated config enables flakes & nix-command"
assert_output_contains "grep -F 'services.fstrim.enable = true;' '$MOCK_CONFIG'" "fstrim" "Generated config enables auto-TRIM"
assert_output_contains "grep -F 'services.flatpak.enable = true;' '$MOCK_CONFIG'" "flatpak" "Generated config enables Flatpak"
assert_output_contains "grep -F 'system.stateVersion' '$MOCK_CONFIG'" "stateVersion" "Generated config defines stateVersion"
