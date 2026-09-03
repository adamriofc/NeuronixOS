# NEURONIX OS Technical Architecture

> **Document ID:** `NRX-ARCH-001`  
> **Status:** APPROVED  
> **Target Audience:** Systems Engineers, Kernel Developers, and Distribution Maintainers  

---

## 1. Executive Summary

NEURONIX OS is an opinionated, production-grade Linux distribution engineered on top of NixOS. It eliminates the configuration complexity traditionally associated with purely functional operating systems by combining an automated graphical installer (Calamares), declarative hardware optimization profiles, and an integrated system control center, while preserving NixOS mathematical reproducibility, declarative configuration, and atomic rollback guarantees.

---

## 2. 4-Layer Platform Architecture

The distribution is structured across four decoupled architectural layers:

```text
                                  NEURONIX PLATFORM
                                          │
       ┌──────────────────────────────────┴──────────────────────────────────┐
       │                                                                     │
   UX LAYER                                                             SYSTEM LAYER
       │                                                                     │
  • Calamares Installer (Flake-Generating)                              • NixOS Pure Substrate
  • NEURONIX Control Center (GUI System Center)                         • Declarative Flakes
  • First-Boot Welcome App & Hardware Profiler                          • Content-Addressed Store
  • Dual-Layer Software Marketplace (Flatpak)                           • Atomic Generations & Rollback
  • One-Click Developer Stacks (neuronix dev)                           • nix-ld Global Dynamic Loader
       │                                                                     │
       └──────────────────────────────────┬──────────────────────────────────┘
                                          │
                                INFRASTRUCTURE LAYER
                                          │
                      • Hermetic ISO Image Compilation
                      • Automated CI/CD Headless QEMU VM Testing
                      • Automated Installer & Desktop Smoke Tests
                      • Hardware Driver Matrix (NVIDIA/PRIME/Wi-Fi)
                      • Architecture Decision Records (ADR-001 - 005)
```

### Layer Responsibilities

| Layer Name | Key Components | Engineering Role |
| :--- | :--- | :--- |
| **UX Layer** | Calamares, `neuronix-center`, `neuronix dev` | Provides zero-friction onboarding, graphical telemetry, and one-command developer environments. |
| **System Layer** | NixOS substrate, Nix Flakes, `nix-ld`, systemd | Manages immutable closures, cryptographic package hashing, and foreign binary execution. |
| **Infrastructure Layer** | Headless QEMU test harness, ISO compilation pipeline | Validates derivation integrity, hardware drivers, and regression prevention before release. |
| **Hardware Abstraction** | 27 declarative hardware and service modules | Adapts kernel, audio, memory, and graphics subsystems to target machine characteristics. |

---

## 3. Declarative Module Structure (`modules/`)

The distribution codebase enforces strict modular separation. Every system capability is isolated into a declarative NixOS module under the `modules/` hierarchy:

```text
modules/
├── core/
│   └── default.nix           # Dynamic loader (nix-ld), unfree licensing, generation prompt
├── desktop/
│   ├── gnome.nix             # GNOME Wayland desktop environment and GDM display manager
│   ├── hyprland.nix          # Dynamic Waybar tiling compositor with XWayland support
│   └── kde.nix               # Flagship KDE Plasma 6 Wayland desktop and SDDM integration
├── hardware/
│   ├── audio.nix             # PipeWire, WirePlumber, Bluetooth LDAC/LC3Plus codecs, DAC pop fix
│   ├── boot.nix              # systemd-boot ESP management (15 generations), Windows dual-boot RTC
│   ├── cpu.nix               # Automated microcode updates for Intel and AMD processors
│   ├── firmware.nix          # Offline redistributable firmware (Broadcom, Realtek, Intel, MediaTek)
│   ├── nvidia-prime.nix      # Hybrid GPU offload (PRIME) and hardware video acceleration (VA-API)
│   ├── power.nix             # S0ix Modern Standby sleep management and 80% battery threshold
│   └── secureboot.nix        # Lanzaboote UEFI Secure Boot signing chain integration (Experimental)
└── services/
    ├── desktop-tweaks.nix    # HiDPI/4K Fractional Scaling (Ozone) and Fcitx5 multilingual IME
    ├── flatpak.nix           # Flathub remote repository, DRI GPU access, and portals.conf mapping
    ├── memory-shield.nix     # ZRAM ZSTD compression, systemd-oomd pressure monitoring, VM tuning
    ├── network.nix           # Public Wi-Fi captive portal detection and enterprise Root CA helper
    ├── printing.nix          # Driverless network printing and scanning (Apple AirPrint / Mopria IPP)
    ├── security.nix          # PolKit graphical privilege escalation, GPG Agent, and Wayland SSH
    └── storage.nix           # Btrfs maintenance balance timer, auto-TRIM, and NTFS/exFAT drivers
```

---

## 4. Virtual Memory Subsystem & Active Memory Shield

NEURONIX implements an aggressive in-RAM compression architecture combined with kernel Pressure Stall Information (PSI) to prevent desktop freezes during heavy compilation or multitasking workloads.

### Kernel Sysctl Parameters

| Parameter | Standard Value | NEURONIX Value | Rationale |
| :--- | :--- | :--- | :--- |
| `vm.swappiness` | `60` | `180` | Aggressively swaps cold memory pages into ZRAM to preserve physical RAM for active hot processes. |
| `vm.page-cluster` | `3` (8 pages) | `0` (1 page) | Eliminates sequential readahead latency since ZRAM is backed by low-latency RAM rather than spinning disks. |
| `vm.vfs_cache_pressure` | `100` | `50` | Retains cached filesystem dentries and inodes in memory, speeding up repeated Git and compilation operations. |
| `vm.max_map_count` | `65530` | `2147483642` | Matches SteamOS and enterprise database standards to prevent memory mapping exhaustion in gaming and IDEs. |
| `fs.file-max` | `default` | `2097152` | Expands system-wide open file descriptor capacity for high-concurrency microservices and IDE build tools. |

### Memory Shield Execution Topology

```text
  Physical RAM Capacity
  ┌──────────────────────────────────────────────────────────┐
  │ 100% Compressed ZRAM Swap Block Device (/dev/zram0)      │
  │ Algorithm: Zstandard (ZSTD) Compression Ratio: ~2.5x-3x   │
  └──────────────────────────────────────────────────────────┘
                               │
                               ▼
  systemd-oomd (PSI Memory Pressure Monitoring)
  ┌──────────────────────────────────────────────────────────┐
  │ Monitors /system.slice and /user.slice pressure thresholds│
  │ Kills memory-leaking runaway cgroups before freeze occurs │
  └──────────────────────────────────────────────────────────┘
```

---

## 5. Storage Topology & Btrfs Subvolume Layout

Storage is organized across five standardized Btrfs subvolumes to isolate mutable user states from the operating system closure and enable atomic snapshot capabilities:

| Subvolume | Mount Point | Mount Options | Engineering Function |
| :--- | :--- | :--- | :--- |
| `@` | `/` | `compress=zstd:3,noatime,space_cache=v2` | Operating system root, Nix profile symlinks, and configuration anchors. |
| `@nix` | `/nix` | `compress=zstd:3,noatime` | Deduplicated, content-addressed `/nix/store` closure data. |
| `@home` | `/home` | `compress=zstd:3,noatime` | User profiles, home directories, project repositories, and personal data. |
| `@snapshots`| `/.snapshots` | `compress=zstd:3,noatime` | Isolated repository for atomic Btrfs filesystem snapshots. |
| `@swap` | `/swap` | `nodatacow,noatime` | Dedicated swapfile storage with Copy-on-Write explicitly disabled. |
| (ESP) | `/boot` | `fmask=0077,dmask=0077` | 1.0 GiB FAT32 EFI System Partition with 15-generation retention limit. |

---

## 6. Execution Model: Pure Declarative Substrate & Foreign Binary ABI

### The `nix-ld` Global Dynamic Linker
Standard pre-compiled Linux binaries (such as VS Code extensions, downloaded Go binaries, and proprietary game runtimes) fail on generic NixOS because the hardcoded `/lib64/ld-linux-x86-64.so.2` ELF dynamic interpreter does not exist in standard FHS paths.

NEURONIX resolves this transparently:
1. `programs.nix-ld.enable = true` installs an intelligent stub at `/lib64/ld-linux-x86-64.so.2`.
2. When a foreign ELF binary is invoked, `nix-ld` intercepts the dynamic library resolution.
3. Libraries are resolved against the declared `nix-ld.libraries` closure containing standard C/C++ runtimes, X11, Wayland, and graphics drivers.
4. Developers run foreign pre-compiled binaries out-of-the-box without containerization overhead.

---

## 7. Dual-Layer Application Delivery Model

To ensure desktop stability without compromising application freshness, NEURONIX separates system software from user desktop applications:

```text
┌──────────────────────────────────────────────────────────────┐
│                     USER DESKTOP APPLICATIONS                 │
│         Flatpak + Flathub Marketplace (via Discover/GNOME)   │
│   • Instant sandboxed updates without recompilation          │
│   • Zero risk of desktop library dependency hell             │
│   • Wayland-native portal isolation (xdg-desktop-portal)     │
├──────────────────────────────────────────────────────────────┤
│                   CORE OPERATING SYSTEM & TOOLING            │
│               Declarative NixOS Flake & Nixpkgs              │
│   • Content-addressed store (/nix/store)                     │
│   • Hermetic, reproducible builds                            │
│   • Atomic generations and instantaneous rollback            │
└──────────────────────────────────────────────────────────────┘
```

---

## 8. Security & Privilege Boundaries

1. **Kernel-Enforced Immutability:** `/nix/store` is mounted read-only at the kernel VFS level. Neither unprivileged users nor processes running with root permissions can modify package files directly.
2. **Privilege Separation:** The primary desktop user belongs to the `wheel` administrative group with mandatory password authentication for PolKit and `sudo` operations.
3. **Nix Daemon Access Restriction:** The `nix-daemon` only accepts commands from trusted users (`root` and `@wheel`), preventing unauthorized derivations from being registered into the local store.
4. **Wayland Display Isolation:** Window management operates under Wayland compositors (KWin, Mutter, Hyprland), preventing cross-window keylogging and unauthorized screen capture between processes.
