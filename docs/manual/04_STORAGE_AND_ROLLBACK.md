# Chapter 4: Storage Architecture & Atomic Rollback Engine

## 1. Btrfs Subvolume Topology

NEURONIX OS partitions physical disks using an opinionated, production-grade Btrfs subvolume layout created during installation via Calamares:

```text
/dev/disk/by-uuid/<UUID> (Btrfs root filesystem)
  ├── subvol=@          -> Mounted at /         (compress=zstd:3, noatime, space_cache=v2)
  ├── subvol=@home      -> Mounted at /home     (compress=zstd:3, noatime)
  ├── subvol=@nix       -> Mounted at /nix      (compress=zstd:3, noatime)
  ├── subvol=@snapshots -> Mounted at /.snapshots
  └── subvol=@swap      -> Mounted at /swap     (nodatacow, noatime)
```

### Critical Invariants:
1. **Subvolume Separation:** The immutable package store (`@nix`) and root operating system (`@`) are strictly separated from user data (`@home`).
2. **Transparent Compression:** `compress=zstd:3` reduces physical NVMe write wear by 30-45% and improves read throughput on solid-state drives.
3. **No CoW on Swap:** The dedicated `@swap` subvolume enforces `nodatacow` (Copy-on-Write disabled) to prevent filesystem fragmentation when using swapfiles.

---

## 2. Atomic Generation Rollback State Machine

Every rebuild in NEURONIX OS creates a discrete system generation:

```text
  [Active: Gen #42]  <─── Active system symlink (/nix/var/nix/profiles/system)
         │
         ▼ (User/AI triggers: neuronix undo)
  [Target: Gen #41]  <─── Symlink swapped atomically (< 100ms)
         │
         ▼ (Reboot or switch)
  [Bootloader Menu]  <─── Previous kernel, modules, and systemd config loaded
```

### Rollback Execution:
```bash
# Instant active profile symlink rollback
neuronix undo

# Equivalent declarative invocation
sudo nixos-rebuild switch --rollback

# Query generational timeline
neuronix generations
```

---

## 3. Autonomous Storage Maintenance

NEURONIX schedules recurring storage maintenance services via systemd timers:

* **Periodic TRIM (`fstrim.timer`):** Issues NVMe/SCSI block discard signals daily to sustain peak SSD read/write speeds.
* **Store Deduplication:** Hardlink deduplication merges identical package store files automatically (`auto-optimise-store = true`).
* **Btrfs Balancing (`neuronix-btrfs-balance.timer`):** Balances underallocated chunk blocks monthly to reclaim unallocated filesystem space.
* **Manual Maintenance:** Run `neuronix diet` anytime to trigger all reclamation steps sequentially.
