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
  ├─ Conductor in foot / Center maintenance GUI                  ├─ Hardware Hardening & Compatibility Matrix
  ├─ First-Boot Welcome, Doctor Diagnostics & Quickstart Hub      ├─ Global Dynamic Linker (nix-ld)
  ├─ Declarative Kernel Manager (zen, lts, latest, hardened)      ├─ Atomic Symlink Pointer Management
  ├─ Dual-Layer Software Model (Nix Core + Flathub Flatpak)       └─ Generation-Aware Shell Prompt [Gen #N]
  └─ Neuronix Session: greetd + Sway / Wayland
  │                                                                                 │
  ├─────────────────────────────────────────────────────────────────────────────────┤
  │                                                                                 │
[ LAYER 3: DEVELOPER ENGINE ]                                   [ LAYER 4: RELIABILITY, PROVABLE STATE & HYPERION ]
  ├─ neuronix dev python (uv, ruff, pyright, postgresql)          ├─ Provable State Engine (5-Leaf Merkle StateRoot)
  ├─ neuronix dev rust   (rustc, cargo, rust-analyzer, clippy)   ├─ Project Hyperion (Adaptive Execution Architecture)
  ├─ neuronix dev node   (node 20, pnpm, typescript, eslint)      ├─ Micro-Rust Systems Daemon (ast.sock)
  ├─ neuronix dev ai     (pytorch, cuda, ollama, jupyterlab)      ├─ Model Context Protocol (MCP) Server (JSON-RPC 2.0)
  ├─ neuronix dev go     (compiler, gopls, golangci-lint, delve)  ├─ In-Memory OS Sandbox (neuronix sandbox / try)
  └─ neuronix container  (Micro-DNS, OCI Build, Quadlet Daemons)  └─ 1,384 Automated Test Assertions (32 Master Suites)
```

---

### Canonical Session Boundary

The default live ISO, installed host configurations, and installer-generated Neuronix profile share `modules/desktop/neuronix.nix`. NixOS supplies the declarative substrate; greetd and Sway/Wayland host the Neuronix experience. foot provides the graphical terminal window required by the current Conductor TTY surface. Center is a distinct maintenance GUI, and Calamares is an on-demand live-only installation action.

Live auto-login is limited to the `nixos` live account. Installed sessions require authentication and support locking. GNOME, KDE, and Hyprland remain explicit compatibility profiles. Session composition does not grant additional control-plane authority or couple agent tasks to the visual process lifetime.

See [ADR-012](../adr/ADR-012-canonical-neuronix-session.md) for the decision and the [graphical qualification runbook](../operations/11_graphical_session_qualification.md) for live-to-installed identity checks. Configuration tests alone do not qualify boot or display behavior.

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
