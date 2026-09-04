# NEURONIX Specification: System Architecture & Technical Specifications

> **Document ID:** `NRX-ARCH-002`  
> **Status:** APPROVED  
> **Path:** `docs/specifications/02_SYSTEM_ARCHITECTURE.md`  

---

## 1. Architectural Model: The 4-Layer Operating System Platform

NEURONIX is organized into four distinct architectural layers, ensuring clear boundaries between user interface, core system configuration, developer runtimes, and validation engines.

```text
                                  NEURONIX OS PLATFORM
                                           │
  ┌────────────────────────────────────────┴────────────────────────────────────────┐
  │                                                                                 │
[ LAYER 1: USER EXPERIENCE (UX) ]                               [ LAYER 2: DESKTOP & SYSTEM CORE ]
  ├─ Calamares Graphical Installer (Declarative Generator)        ├─ Pure Nix Substrate (Immutable /nix/store)
  ├─ NEURONIX Center (GUI System Hub & Telemetry)                 ├─ Hardware Hardening & Compatibility Matrix
  ├─ Generation Management & Instant Rollbacks (< 2s)             ├─ Global Dynamic Linker (nix-ld)
  ├─ Dual-Layer Software Model (Nix Core + Flathub Flatpak)       ├─ Atomic Symlink Pointer Management
  └─ Desktop Environments: KDE Plasma 6, GNOME, Hyprland          └─ Generation-Aware Shell Prompt [Gen #N]
  │                                                                                 │
  ├─────────────────────────────────────────────────────────────────────────────────┤
  │                                                                                 │
[ LAYER 3: DEVELOPER ENGINE ]                                   [ LAYER 4: RELIABILITY & AI SUBSTRATE ]
  ├─ neuronix dev python (uv, ruff, pyright, postgresql)          ├─ Model Context Protocol (MCP) Server (JSON-RPC 2.0)
  ├─ neuronix dev rust   (rustc, cargo, rust-analyzer, clippy)   ├─ In-Memory Shadow Micro-VM Simulator (neuronix try)
  ├─ neuronix dev node   (node 20, pnpm, typescript, eslint)      ├─ Dry-Build Formal Verification (neuronix verify)
  ├─ neuronix dev ai     (pytorch, cuda, ollama, jupyterlab)      ├─ Storage Pruner & VirtIO TRIM (neuronix diet)
  └─ neuronix dev go     (compiler, gopls, golangci-lint, delve)  └─ 821 Automated Test Cases (100% Pass)
```

---

## 2. Storage Subsystem & Btrfs Architecture

NEURONIX partitions target storage using a standardized Btrfs subvolume layout:

| Subvolume | Mount Point | Options | Operational Function |
| :--- | :--- | :--- | :--- |
| `@` | `/` | `compress=zstd:3,noatime,space_cache=v2` | Operating system root files and immutable configuration pointers. |
| `@nix` | `/nix` | `compress=zstd:3,noatime` | Deduplicated and compressed `/nix/store`. |
| `@home` | `/home` | `compress=zstd:3,noatime` | User data, projects, and personal dotfiles. |
| `@snapshots` | `/.snapshots` | `compress=zstd:3,noatime` | Storage repository for atomic filesystem snapshots. |
| `@swap` | `/swap` | `nodatacow,noatime` | Dedicated swapfile subvolume with Copy-on-Write disabled. |

### Storage Reclamation Lifecycle
1. **Auto-TRIM (`fstrim.timer`):** Issues SCSI/VirtIO discard commands daily across mounted partitions.
2. **Garbage Collection (`nix-gc.timer`):** Purges unreferenced package profiles and dead derivation closures.
3. **Hardlink Inode Deduplication (`auto-optimise-store = true`):** Automatically hardlinks identical binary files across derivations.
4. **Metadata Balance (`btrfs-balance.timer`):** Compacts empty block groups monthly to prevent `ENOSPC` errors.

---

## 3. Active Memory Management Architecture

To prevent system lockups during high memory load:
- **ZRAM Compressed Swap Pool:** Allocates an in-RAM block device equal to 100% of physical RAM capacity using the ZSTD compression algorithm.
- **Kernel Swapping Tuning:** Configures `vm.swappiness = 180` and `vm.page-cluster = 0` to move idle anonymous pages to compressed ZRAM early.
- **Pressure Stall Information (PSI) & systemd-oomd:** Samples kernel stall metrics (`/proc/pressure/memory`) and terminates rogue processes within 50 ms when memory pressure exceeds 10% for over 10 seconds.

---

## 4. Hardware Profile Integration

Hardware compatibility is implemented declaratively in `modules/`:
- **Firmware:** Full redistributable firmware bundle (`hardware.enableAllFirmware = true`).
- **NVIDIA PRIME:** Automated render offload for hybrid GPU laptops.
- **Power:** Kernel directive `mem_sleep_default=deep` and `power-profiles-daemon` for Modern Standby battery conservation.
- **Audio:** Low-latency PipeWire session management supporting LDAC, AptX HD, and LC3Plus Bluetooth codecs.
- **Battery:** Hardware charge ceiling daemon setting sysfs `charge_control_limit_max = 80`.
