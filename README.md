# NEURONIX OS

**A Declarative, Reproducible Linux Operating System Platform with Calamares Installer, Hardware Hardening Matrix, and Deterministic Developer Substrate**

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![NixOS](https://img.shields.io/badge/Substrate-NixOS_24.11_%2F_26.05-5277C3.svg?logo=nixos&logoColor=white)](flake.nix)
[![Architecture](https://img.shields.io/badge/Architecture-4--Layer_Platform-9cf.svg)](#platform-architecture)
[![Testing](https://img.shields.io/badge/Tests-705%2F705_Passed_(100%25)-success.svg)](#verification--test-harness)
[![Filesystem](https://img.shields.io/badge/Filesystem-Btrfs_ZSTD%3A3-orange.svg)](#storage-architecture--autonomous-lifecycle)
[![Memory Management](https://img.shields.io/badge/Memory_Subsystem-ZRAM_ZSTD_%2B_PSI-purple.svg)](#active-memory-pressure-architecture)
[![CI/CD](https://img.shields.io/badge/CI%2FCD-GitHub_Actions_Passing-brightgreen.svg)](.github/workflows/ci.yml)

---

## Table of Contents

- [Overview](#overview)
- [Platform Architecture](#platform-architecture)
- [Storage Architecture & Autonomous Lifecycle](#storage-architecture--autonomous-lifecycle)
  - [Btrfs Subvolume Topology](#btrfs-subvolume-topology)
  - [Transparent Block Compression (ZSTD:3)](#transparent-block-compression-zstd3)
  - [Autonomous Storage Pruning & Host SSD TRIM (Auto-TRIM)](#autonomous-storage-pruning--host-ssd-trim-auto-trim)
  - [Periodic Metadata Balance Timer](#periodic-metadata-balance-timer)
- [Active Memory Pressure Architecture](#active-memory-pressure-architecture)
  - [ZRAM In-Memory Compressed Swap Pool](#zram-in-memory-compressed-swap-pool)
  - [Aggressive Swapping Tuning (`vm.swappiness = 180`)](#aggressive-swapping-tuning-vmswappiness--180)
  - [Kernel Pressure Stall Information (PSI) & systemd-oomd](#kernel-pressure-stall-information-psi--systemd-oomd)
- [Hardware Compatibility & Subsystem Hardening Matrix](#hardware-compatibility--subsystem-hardening-matrix)
- [Comprehensive Command-Line Reference (`neuronix`)](#comprehensive-command-line-reference-neuronix)
- [Core System Components](#core-system-components)
  - [1. Declarative Calamares Installation Engine](#1-declarative-calamares-installation-engine)
  - [2. System Control Center (`neuronix-center`)](#2-system-control-center-neuronix-center)
  - [3. Isolated Development Environments (`neuronix dev`)](#3-isolated-development-environments-neuronix-dev)
  - [4. Ephemeral In-Memory Micro-VM Simulation (`neuronix try`)](#4-ephemeral-in-memory-micro-vm-simulation-neuronix-try)
  - [5. Model Context Protocol (MCP) Server](#5-model-context-protocol-mcp-server)
- [Building & Installation](#building--installation)
- [Post-Installation Administration](#post-installation-administration)
- [Verification & Test Harness (705 Tests)](#verification--test-harness)
- [Architecture Decision Records (ADRs)](#architecture-decision-records-adrs)
- [License](#license)

---

## Overview

**NEURONIX OS** is a declarative, reproducible Linux operating system platform built upon the NixOS kernel and packaging infrastructure. It bridges pure-functional package management and atomic system transitions with an automated graphical installation workflow, integrated hardware profiles, and developer execution engines.

The platform architecture is structured into four cohesive layers:
1. **User Experience Layer:** Graphical system installer powered by Calamares, visual generation inspection, and curated desktop configurations (KDE Plasma 6, GNOME Wayland, and Hyprland).
2. **System Core Layer:** Read-only immutable store (`/nix/store`), declarative hardware and kernel modules, global dynamic linker (`nix-ld`), and dual-layer software management (Nix core + Flatpak).
3. **Developer Engine Layer:** One-command isolated development toolchains (`neuronix dev`), atomic storage optimization, and system profile controls.
4. **Reliability & AI Substrate Layer:** In-memory ephemeral micro-VM simulation (`neuronix try`), Model Context Protocol (MCP) server for automated system telemetry, and continuous test verification.

---

## Platform Architecture

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
  ├─ neuronix dev node   (node 20, pnpm, typescript, eslint)      ├─ Zero-Blast Formal Proof Verification (neuronix verify)
  ├─ neuronix dev ai     (pytorch, cuda, ollama, jupyterlab)      ├─ Autonomous Storage Pruner & VirtIO TRIM (neuronix diet)
  └─ neuronix dev go     (compiler, gopls, golangci-lint, delve)  └─ 705 Automated Industrial Verification Assertions
```

---

## Storage Architecture & Autonomous Lifecycle

Storage management in immutable and functional operating systems requires proactive maintenance to prevent disk expansion, file duplication, and SSD wear. NEURONIX implements an autonomous, multi-tier storage subsystem.

### Btrfs Subvolume Topology
The installation engine partitions storage utilizing a standardized Btrfs subvolume architecture designed for isolation, backup atomicity, and performance:

| Subvolume | Mount Point | Mount Options | Purpose |
| :--- | :--- | :--- | :--- |
| `@` | `/` | `compress=zstd:3,noatime,space_cache=v2` | Operating system root files and immutable configuration pointers. |
| `@nix` | `/nix` | `compress=zstd:3,noatime` | The cryptographic, content-addressed `/nix/store`. Deduplicated and compressed. |
| `@home` | `/home` | `compress=zstd:3,noatime` | User data, projects, dotfiles, and personal documents. |
| `@snapshots` | `/.snapshots` | `compress=zstd:3,noatime` | Atomic Btrfs snapshot repository for system rollback checkpoints. |
| `@swap` | `/swap` | `nodatacow,noatime` | Dedicated swapfile subvolume. Copy-on-Write is strictly disabled to prevent fragmentation and hibernation image corruption. |

### Transparent Block Compression (ZSTD:3)
All read-write filesystem trees are mounted with in-kernel **Zstandard level 3 (`zstd:3`) compression**.
- **Footprint Reduction:** Reduces the physical storage consumption of `/nix/store` derivations and libraries by **40% to 50%**.
- **I/O Throughput Amplification:** Reading compressed blocks from modern NVMe/SATA storage reduces raw byte transfer volume, effectively increasing real-world read/write throughput while lowering wear cycles on solid-state NAND cells.

### Autonomous Storage Pruning & Host SSD TRIM (Auto-TRIM)
Solid-state drives and virtualized sparse disk images (such as QEMU/KVM `.qcow2` or raw disk images) suffer from space ballooning when deleted blocks are not released to the underlying storage controller.

NEURONIX automates storage reclamation across three coordinated lifecycle phases:
1. **Automated TRIM Daemon (`fstrim.timer`):** Runs daily as a systemd timer, issuing SCSI/VirtIO unmap commands (`fstrim -av`) across all mounted Btrfs and ESP partitions. This informs the host SSD or hypervisor of deallocated blocks, reclaiming host physical storage and optimizing flash wear leveling.
2. **Automated Garbage Pruning (`nix-gc.timer`):** Executes periodic cleanup cycles, purging unreferenced derivation links and dead package profiles.
3. **Continuous Inode Deduplication (`auto-optimise-store = true`):** Automatically hardlinks identical binary files across derivations within `/nix/store`, eliminating storage waste from duplicated shared libraries across different package closures.

### Periodic Metadata Balance Timer
Btrfs allocates storage in coarse-grained chunks (data chunks and metadata chunks). Over months of package updates, empty allocations can cause premature `ENOSPC` (No space left on device) errors despite free physical space.
- NEURONIX incorporates an automated **`btrfs-balance.timer`** running on a monthly schedule (`OnCalendar=monthly`, `Persistent=true`).
- It filters and compacts under-allocated block groups (`btrfs balance start -dusage=10 -musage=10 /`), ensuring long-term filesystem health without user intervention.

---

## Active Memory Pressure Architecture

Standard desktop Linux environments frequently suffer from complete system freezes or mouse cursor lockups when memory is exhausted, caused by kernel page thrashing (`kswapd` high CPU utilization while scanning memory). 

NEURONIX implements an active three-tier memory protection matrix:

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│                       ACTIVE MEMORY PRESSURE MATRIX                         │
└─────────────────────────────────────────────────────────────────────────────┘
                                       │
        ┌──────────────────────────────┼──────────────────────────────┐
        ▼                              ▼                              ▼
  [ TIER 1: POOL ]              [ TIER 2: TUNING ]             [ TIER 3: GUARD ]
  ZRAM Swap Pool (100% RAM)     vm.swappiness = 180            systemd-oomd (PSI)
  Compression: ZSTD             vm.page-cluster = 0            Path: /proc/pressure/memory
  Speed: Memory-bus speed       vm.vfs_cache_pressure = 50     Threshold: > 10% for 10s
  Swap space: ~2.5x physical    Action: Compress idle pages    Action: Terminate rogue task
                                early into ZRAM                Latency: < 50ms (No freeze)
```

### ZRAM In-Memory Compressed Swap Pool
- Allocates an in-RAM virtual compressed block device up to **100% of physical RAM capacity** using the `zram-generator`.
- Employs the **ZSTD** compression algorithm, providing an effective swap pool size $\approx 2.5\times$ to $3\times$ larger than uncompressed memory with microsecond latency.

### Aggressive Swapping Tuning (`vm.swappiness = 180`)
- Standard Linux defaults (`swappiness = 60`) delay swapping until memory is critically low, forcing catastrophic disk thrashing.
- Setting `vm.swappiness = 180` and `vm.page-cluster = 0` encourages the kernel to compress inactive background memory pages into ZRAM early, reserving raw physical RAM for active foreground processes and compilers.

### Kernel Pressure Stall Information (PSI) & systemd-oomd
- The system continuously samples hardware stall metrics via kernel Pressure Stall Information (`/proc/pressure/memory`).
- If memory stall pressure exceeds a 10% threshold for longer than 10 seconds, `systemd-oomd` deterministically identifies and terminates the specific rogue cgroup consumer within **50 milliseconds**, completely eliminating unrecoverable desktop freezes.

---

## Hardware Compatibility & Subsystem Hardening Matrix

NEURONIX encapsulates modular, declarative profiles addressing common desktop and mobile workstation configurations:

| Subsystem Domain | Technical Objective | Declarative Implementation | Configuration Module |
| :--- | :--- | :--- | :--- |
| **Package Licensing** | Proprietary drivers and runtime compatibility (Steam, NVIDIA, codecs) | `nixpkgs.config.allowUnfree = true` | `modules/core/default.nix` |
| **RTC Synchronization** | Real-time clock synchronization in multi-boot environments | `time.hardwareClockInLocalTime = true` | `modules/hardware/boot.nix` |
| **Filesystem Maintenance** | Metadata chunk fragmentation prevention on active Btrfs volumes | Automated monthly `btrfs-balance` systemd timer | `modules/services/storage.nix` |
| **Storage Reclamation** | Autonomous SSD TRIM and sparse disk reclamation (Auto-TRIM) | Daily `fstrim.timer` + `auto-optimise-store` hardlink dedupe | `modules/services/storage.nix` |
| **Application Ecosystem** | Sandboxed graphical application integration without root mutation | Dual-layer distribution: immutable Nix core + Flathub Flatpak | `modules/services/flatpak.nix` |
| **Boot Partition Guard** | EFI System Partition storage overflow prevention | 1.0 GiB ESP standard with generation prune threshold (`configurationLimit = 15`) | `modules/hardware/boot.nix` |
| **Offline Firmware** | Out-of-the-box Wi-Fi and Bluetooth chipset connectivity | Full redistributable firmware bundle (Broadcom, Realtek, Intel) | `modules/hardware/firmware.nix` |
| **Hybrid Graphics** | Dynamic dGPU power gating on Optimus/PRIME laptops | Automated NVIDIA PRIME Render Offload configuration | `modules/hardware/nvidia-prime.nix` |
| **Secure Boot** | Compatibility with UEFI Secure Boot firmware policies | Signed `shim` integration via `lanzaboote` | `modules/hardware/boot.nix` |
| **Portal Integration** | Native file-chooser dialog synchronization under Wayland | Explicit portal backend mapping via `portals.conf` | `modules/services/flatpak.nix` |
| **Power Management** | Modern Standby battery drain reduction on mobile hardware | Kernel directive `mem_sleep_default=deep` + `power-profiles-daemon` | `modules/hardware/power.nix` |
| **Dual Boot Detection** | UEFI boot partition discovery for multi-boot operating systems | Native `systemd-boot` EFI discovery without legacy os-prober | `modules/hardware/boot.nix` |
| **Memory Mapping Limit** | Thread allocation and memory map exhaustion prevention | High-concurrency tuning: `vm.max_map_count = 2147483642` | `modules/hardware/boot.nix` |
| **HiDPI Display Scaling** | Subpixel and fractional scaling blur elimination under Wayland | Wayland Ozone flags enabled for Chromium and Electron runtimes | `modules/services/desktop-tweaks.nix` |
| **Boot Watchdog** | Power-loss protection during bootloader update transactions | Hardware UEFI watchdog timeouts (`30s` runtime, `10min` reboot) | `modules/hardware/boot.nix` |
| **Input Methods** | Multilingual text input support (CJK and complex scripts) | Pre-configured Fcitx5 IME framework | `modules/services/desktop-tweaks.nix` |
| **Trust Store Injection** | Corporate and development Root CA certificate enrollment | Dedicated certificate injection script (`neuronix-add-ca`) | `modules/services/network.nix` |
| **Memory Pressure Guard** | System responsiveness and freeze prevention under memory saturation | ZRAM compressed RAM swap (ZSTD, 100% RAM) + `systemd-oomd` PSI | `modules/services/memory-shield.nix` |
| **Audio Processing** | Low-latency audio processing and high-fidelity Bluetooth communication | PipeWire session manager with LDAC, AptX HD, and LC3Plus codecs | `modules/hardware/audio.nix` |
| **Battery Conservation** | Battery cycle life extension during prolonged AC operation | Kernel sysfs charge ceiling daemon (`charge_control_limit_max = 80`) | `modules/hardware/power.nix` |
| **Video Decoding** | Hardware-accelerated video decode offloading (H.264, HEVC, AV1) | Pre-configured VA-API and NVDEC acceleration libraries | `modules/hardware/nvidia-prime.nix` |
| **Network Portals** | Captive portal detection on public and enterprise Wi-Fi | Automated NetworkManager connectivity polling | `modules/services/network.nix` |
| **Printing Subsystem** | Driverless network and USB printing | IPP Everywhere, Apple AirPrint, and Mopria service integration | `modules/services/printing.nix` |
| **External Media** | High-performance removable storage throughput | In-kernel `ntfs3` and native `exfat` automounting | `modules/services/storage.nix` |
| **Analog Audio Power** | DAC click and pop elimination on 3.5mm analog outputs | Inactive DAC power-save state disabled (`snd_hda_intel power_save=0`) | `modules/hardware/audio.nix` |
| **Swap Integrity** | Filesystem corruption prevention on Btrfs swapfiles | Dedicated `@swap` subvolume with Copy-on-Write disabled (`nodatacow`) | `installer/calamares/modules/partition.conf` |
| **Microcode Updates** | Processor security vulnerability mitigations (Spectre, Zenbleed) | Automated processor microcode updates enabled for Intel and AMD | `modules/hardware/cpu.nix` |
| **Identity & Signing** | Secure cryptographic key agent forwarding on Wayland sessions | GnuPG Agent with Pinentry graphical prompt and `SSH_AUTH_SOCK` | `modules/services/security.nix` |

---

## Comprehensive Command-Line Reference (`neuronix`)

NEURONIX includes an integrated system utility (`neuronix`) providing diagnostic telemetry, storage optimization, developer workspaces, and generation control.

```text
USAGE:
  neuronix <COMMAND> [OPTIONS]
```

### Core Commands

| Command | Arguments | Description | Example |
| :--- | :--- | :--- | :--- |
| `status` | None | Displays system identity, kernel version, storage health, systemd timers, and hardware shield status. | `neuronix status` |
| `shield` | None | Diagnoses memory pressure metrics, ZRAM allocation, kernel swappiness, and live PSI saturation. | `neuronix shield` |
| `generations` | None (or `list`) | Displays chronological timeline of all system generations and highlights the currently active generation. | `neuronix generations` |
| `battery` | `[80 \| 100 \| status]` | Inspects or toggles the hardware battery charge threshold limit (sysfs charge control limit). | `neuronix battery 80` |
| `diet` | None | Executes garbage collection, hardlink deduplication across `/nix/store`, and issues filesystem TRIM unmap calls. | `neuronix diet` |
| `dev` | `<stack>` | Provisions an instant, hermetic, zero-pollution development shell in memory (`python`, `rust`, `node`, `ai`, `go`, `web3`). | `neuronix dev rust` |
| `run` | `<packages...>` | Constructs an isolated, temporary subshell containing the requested software packages, purged on exit. | `neuronix run ffmpeg jq` |
| `try` | `[file.nix] [--smoke-test]` | Simulates configuration changes or packages inside an ephemeral in-RAM micro-VM via QEMU and 9P sharing. | `neuronix try --smoke-test` |
| `verify` | `<package>` | Evaluates package existence and derivation validity against nixpkgs closure (Zero-Blast Radius proof). | `neuronix verify ripgrep` |
| `center` | None | Launches the graphical NEURONIX Control Center (or falls back to `--cli` mode if headless). | `neuronix center` |
| `mcp` | None | Initializes the Model Context Protocol (MCP) server over `stdio` adhering to JSON-RPC 2.0. | `neuronix mcp` |
| `undo` | None (or `rollback`) | Instantly rolls back the active system to the preceding generation in $< 2$ seconds. | `neuronix undo` |
| `version` | None (`-v`, `--version`)| Prints system version, metadata, and license details. | `neuronix version` |
| `help` | None (`-h`, `--help`)   | Displays usage instructions and command summaries. | `neuronix help` |

---

## Core System Components

### 1. Declarative Calamares Installation Engine
The graphical installer operates as a **Declarative Flake Generator** rather than an imperative rootfs unpacker ([ADR-002](docs/adr/ADR-002-why-calamares-flake-generator.md)):
- Collects locale, keyboard, user, and disk layout specifications via the Calamares framework.
- Generates reproducible `/mnt/etc/nixos/flake.nix` and `configuration.nix` configurations reflecting host parameters.
- Formats storage using an optimized Btrfs subvolume architecture (`@`, `@nix`, `@home`, `@snapshots`, `@swap`).
- Executes `nixos-install --flake /mnt/etc/nixos#neuronix-desktop`, resulting in an installed system governed declaratively from initial boot.

### 2. System Control Center (`neuronix-center`)
A native system management utility providing administrative controls:
- **Telemetry Dashboard:** Live monitoring of kernel parameters, active Nix generation, processor, graphics adapter, and compression statistics.
- **Generation Management:** Graphical timeline of system generations. Enables instantaneous rollback to preceding generations in $< 2$ seconds without terminal commands.
- **Storage Maintenance:** Orchestrates store garbage collection, hardlink deduplication, and filesystem TRIM operations.
- **Dual Execution Interface:** Supports graphical display (Tkinter/Qt) and headless command-line mode (`neuronix-center --cli`).

### 3. Isolated Development Environments (`neuronix dev`)
Hermetic, content-addressed development workspaces provisioned directly into memory:
```bash
# Provision Python toolchain (Python 3.12, uv, ruff, pyright, postgresql client)
neuronix dev python

# Provision Rust toolchain (rustc, cargo, rust-analyzer, clippy, mold)
neuronix dev rust

# Provision Node.js toolchain (Node.js 20 LTS, pnpm, typescript, eslint)
neuronix dev node

# Provision AI/ML toolchain (PyTorch, CUDA runtimes, Ollama, JupyterLab, pandas)
neuronix dev ai

# Provision Go toolchain (Go compiler, gopls, golangci-lint, delve)
neuronix dev go

# Provision Web3 toolchain (Rust, Cargo, Node.js, solana-cli)
neuronix dev web3
```

### 4. Ephemeral In-Memory Micro-VM Simulation (`neuronix try`)
Enables verification of proposed system configurations, kernel options, or untrusted software inside an ephemeral QEMU micro-VM running entirely in memory (`/dev/shm`) with read-only 9P store pass-through:
```bash
# Execute automated smoke test inside the in-memory Micro-VM
neuronix try --smoke-test

# Evaluate a target configuration file inside an isolated sandbox
neuronix try ./configuration.nix --timeout 60
```

### 5. Model Context Protocol (MCP) Server
NEURONIX includes a built-in Model Context Protocol server communicating over `stdio` adhering to JSON-RPC 2.0 (Protocol Version `2024-11-05`). It provides structured tools for autonomous development agents:
```bash
# Exposes neuronix_status, neuronix_diet, neuronix_verify, neuronix_undo, and neuronix_shadow_eval
neuronix mcp
```

---

## Building & Installation

### Building the Installation Medium
To compile the official Live ISO installer image using Nix Flakes:
```bash
git clone https://github.com/adamriofc/neuronix.git
cd neuronix

# Build Live ISO with Calamares graphical installer
nix build .#packages.x86_64-linux.iso
```
The resulting bootable image is located at `result/iso/neuronix-os-*.iso`. Flash to installation media:
```bash
sudo dd if=result/iso/neuronix-*.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

### Installation Workflow
1. Boot the target system from the live installation medium.
2. Select driver initialization mode (standard open-source drivers or proprietary NVIDIA drivers).
3. The **Calamares Installer** initializes automatically on the desktop.
4. Select partitioning scheme (automated Btrfs ZSTD:3 layout or manual partition mapping).
5. Configure regional settings, user credentials, and desktop environment (KDE Plasma, GNOME, or Hyprland).
6. Complete installation and reboot into the target environment.

---

## Post-Installation Administration

### Modifying System Configuration
The installed system is fully declarative and configured in `/etc/nixos/`:
```bash
# Edit host configuration
sudo nano /etc/nixos/configuration.nix

# Rebuild and activate new system generation atomically
sudo nixos-rebuild switch --flake /etc/nixos#neuronix-desktop
```

### Managing Application Packages
- **Command-line utilities:** Add package derivations directly to `environment.systemPackages` in `configuration.nix`.
- **Graphical applications:** Discover and install sandboxed applications via KDE Discover or GNOME Software powered by Flathub:
```bash
flatpak install flathub com.spotify.Client
flatpak install flathub org.videolan.VLC
```

### Reclaiming Storage
To run a manual storage optimization cycle:
```bash
neuronix diet
```

---

## Verification & Test Harness (705 Tests)

System invariants, module structures, and CLI dispatchers are validated through an automated test suite comprising **705 assertions across 20 verification suites**:

```text
═══════════════════════════════════════════════════════════════════
                    TEST HARNESS REPORT SUMMARY                    
═══════════════════════════════════════════════════════════════════
  Master Test Harness (tests/run_all_tests.sh)     : 506 / 506 PASS
  Distro Test Harness (tests/test_distro_suite.sh) : 199 / 199 PASS
  Total Executed Tests                             : 705 Tests
  Failed Verification                              : 0 Failures
  Execution Duration                               : ~44.0 seconds
  Confidence Score                                 : 100%
═══════════════════════════════════════════════════════════════════
```

### Verification Coverage:
- **Suites 01–03:** Script syntax, POSIX compliance, static analysis, and generation parsing.
- **Suites 04–06:** Storage subsystem telemetry, ephemeral sandbox isolation, and fault injection.
- **Suites 07–09:** Hermetic Flake reproducibility, environment sanitization (`env -i`), and buffer fuzzing.
- **Suites 10–13:** Filesystem invariants, concurrency race conditions, resource exhaustion (`ulimit`), and state mutations.
- **Suites 14–15:** MCP JSON-RPC 2.0 protocol compliance and micro-VM lifecycle management.
- **Suites 16–17:** Subsystem configuration contracts, kernel sysctl parameters, watchdog timers, and audio codecs.
- **Suite 18:** Command-line argument boundary fuzzing and shell injection neutralization.
- **Suite 19:** Architecture Decision Records (ADRs) and documentation consistency.
- **Suite 20:** Storage subsystem declarations, Btrfs subvolume mount options, and installer generator scripts.

Execute the verification battery:
```bash
# Run master test harness (506 tests)
bash tests/run_all_tests.sh

# Run distribution standalone suite (199 tests)
bash tests/test_distro_suite.sh
```

---

## Architecture Decision Records (ADRs)

Formal design choices and rationales are maintained in `docs/adr/`:
- **[ADR-001](docs/adr/ADR-001-why-flakes.md):** Pure Nix Flakes as the Primary Interface
- **[ADR-002](docs/adr/ADR-002-why-calamares-flake-generator.md):** Declarative Flake Generation within Calamares
- **[ADR-003](docs/adr/ADR-003-immutable-store-vs-flatpak.md):** Dual-Layer Software Architecture (Immutable Nix Core vs Sandboxed Flatpak)
- **[ADR-004](docs/adr/ADR-004-update-channel-strategy.md):** Upstream Synchronization and Fork Mitigation Strategy
- **[ADR-005](docs/adr/ADR-005-hardware-detection-architecture.md):** Hybrid Hardware Detection and Battery Longevity Architecture

---

## License

NEURONIX OS is open-source software licensed under the **Apache License, Version 2.0**. See the [LICENSE](LICENSE) file for complete details.

Copyright (c) 2026 NEURONIX Contributors.
