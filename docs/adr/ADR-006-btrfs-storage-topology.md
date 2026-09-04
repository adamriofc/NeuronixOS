# ADR-006: Structured Btrfs Subvolume Topology and Storage Maintenance

## Status
**Accepted** (Approved for NEURONIX OS Standalone Distribution)

## Context & Problem Statement
Traditional single-partition or unstructured Btrfs deployments combine volatile runtime data, user files, the immutable Nix store, and system swapfiles within an unsegmented filesystem tree. This structure causes operational issues:
1. Snapshotting the root filesystem unintentionally captures gigabytes of temporary cache files and Nix store derivations.
2. Placing swapfiles on standard Copy-on-Write (CoW) Btrfs extents degrades memory paging throughput and risks filesystem corruption.
3. Unbalanced Btrfs metadata chunks over time cause false out-of-space errors even when raw physical disk space remains available.

## Architectural Decision
NEURONIX mandates an isolated subvolume layout across all automated and guided installations:
- `@`: Root subvolume mounted at `/` with default subvolume settings.
- `@home`: User profile directories mounted at `/home` for independent snapshotting and data persistence across system re-installations.
- `@nix`: Dedicated Nix store subvolume mounted at `/nix`, isolating package closures from user backups.
- `@snapshots`: Dedicated storage subvolume mounted at `/.snapshots` reserved for atomic generation recovery.
- `@swap`: Dedicated subvolume mounted at `/swap` with `nodatacow` attribute explicitly set before swapfile allocation.
- Mount flags enforce `compress=zstd:3` for transparent block-level compression and `noatime` to eliminate metadata write amplification on flash storage.
- Systemd timers execute automated SSD TRIM (`fstrim.timer`) on a daily interval and non-disruptive metadata balancing (`btrfs-balance.timer`) on a monthly interval.

## Consequences
- **Positive:** User data snapshots can be created and rolled back in milliseconds without duplicating the multi-gigabyte Nix store; flash storage lifespan is extended via auto-TRIM and noatime; disk utilization decreases by 25% to 40% through transparent Zstandard compression; swapfile operation is fully stable.
- **Trade-off:** Requires Btrfs-aware partition tooling during custom manual installations; users preferring EXT4 must explicitly select the legacy profile via `neuronix.storage.filesystem = "ext4"`.
