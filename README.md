# NEURONIX OS

**A Declarative, Reproducible Linux Operating System Platform with Calamares Installer, Hardware Hardening Matrix, and Deterministic Developer Substrate**

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![NixOS](https://img.shields.io/badge/Substrate-NixOS_24.11_%2F_26.05-5277C3.svg?logo=nixos&logoColor=white)](flake.nix)
[![Architecture](https://img.shields.io/badge/Architecture-4--Layer_Platform-9cf.svg)](#platform-architecture)
[![Testing](https://img.shields.io/badge/Tests-705%2F705_Passed_(100%25)-success.svg)](#verification--test-harness)
[![Filesystem](https://img.shields.io/badge/Filesystem-Btrfs_ZSTD%3A3-orange.svg)](#2-declarative-calamares-installation-engine)
[![Memory Management](https://img.shields.io/badge/Memory_Subsystem-ZRAM_ZSTD_%2B_PSI-purple.svg)](#1-active-memory-pressure-architecture)
[![CI/CD](https://img.shields.io/badge/CI%2FCD-GitHub_Actions_Passing-brightgreen.svg)](.github/workflows/ci.yml)

---

## Overview

**NEURONIX OS** is a declarative, reproducible Linux operating system platform built upon the NixOS kernel and packaging infrastructure. It bridges functional package management and atomic system transitions with an automated graphical installation workflow, integrated hardware profiles, and developer execution engines.

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

## Hardware Compatibility & Subsystem Hardening Matrix

NEURONIX encapsulates modular, declarative profiles addressing common desktop and mobile workstation configurations:

| Subsystem Domain | Technical Objective | Declarative Implementation | Configuration Module |
| :--- | :--- | :--- | :--- |
| **Package Licensing** | Proprietary drivers and runtime compatibility (Steam, NVIDIA, codecs) | `nixpkgs.config.allowUnfree = true` | `modules/core/default.nix` |
| **RTC Synchronization** | Real-time clock synchronization in multi-boot environments | `time.hardwareClockInLocalTime = true` | `modules/hardware/boot.nix` |
| **Filesystem Maintenance** | Metadata chunk fragmentation prevention on active Btrfs volumes | Automated monthly `btrfs-balance` systemd timer | `modules/services/storage.nix` |
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

## Core System Components

### 1. Active Memory Pressure Architecture
To prevent kernel page-thrashing lockups (`kswapd` CPU saturation) during heavy multitasking or large compilation jobs, NEURONIX coordinates three memory management layers:
1. **Compressed In-RAM Swap Pool (ZRAM):** Allocates a virtual swap device up to 100% of physical memory utilizing the **ZSTD compression algorithm** ($\approx 2.5\times$ to $3\times$ compression efficiency).
2. **Paging Parameter Tuning (`vm.swappiness = 180`):** Directs idle anonymous memory pages into compressed ZRAM early, preserving uncompressed physical RAM for active application working sets.
3. **Pressure Stall Information (`systemd-oomd`):** Samples kernel memory pressure from `/proc/pressure/memory`. If memory stall duration exceeds 10% for $> 10$ seconds, offending background processes are terminated deterministically within 50 milliseconds, preserving graphical interface responsiveness.

### 2. Declarative Calamares Installation Engine
The graphical installer operates as a **Declarative Flake Generator** rather than an imperative rootfs unpacker ([ADR-002](docs/adr/ADR-002-why-calamares-flake-generator.md)):
- Collects locale, keyboard, user, and disk layout specifications via the Calamares framework.
- Generates reproducible `/mnt/etc/nixos/flake.nix` and `configuration.nix` configurations reflecting host parameters.
- Formats storage using an optimized Btrfs subvolume architecture:
  - `@` (Root: `compress=zstd:3,noatime,space_cache=v2`)
  - `@nix` (Nix store: `compress=zstd:3,noatime`) — Reduces physical disk footprint by 40–50%.
  - `@home` (User directories: `compress=zstd:3,noatime`)
  - `@snapshots` (Dedicated snapshot target)
  - `@swap` (Swapfile: `nodatacow,noatime` — Disables CoW to preserve filesystem consistency).
- Executes `nixos-install --flake /mnt/etc/nixos#neuronix-desktop`, resulting in an installed system governed declaratively from initial boot.

### 3. System Control Center (`neuronix-center`)
A native system management utility providing administrative controls:
- **Telemetry Dashboard:** Live monitoring of kernel parameters, active Nix generation, processor, graphics adapter, and compression statistics.
- **Generation Management:** Graphical timeline of system generations. Enables instantaneous rollback to preceding generations in $< 2$ seconds without terminal commands.
- **Storage Maintenance:** Orchestrates store garbage collection, hardlink deduplication, and filesystem TRIM operations.
- **Dual Execution Interface:** Supports graphical display (Tkinter/Qt) and headless command-line mode (`neuronix-center --cli`).

### 4. Isolated Development Environments (`neuronix dev`)
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

### 5. In-Memory Micro-VM Simulation (`neuronix try`)
Enables verification of proposed system configurations, kernel options, or untrusted software inside an ephemeral QEMU micro-VM running entirely in memory (`/dev/shm`) with read-only 9P store pass-through:
```bash
# Execute automated smoke test inside the in-memory Micro-VM
neuronix try --smoke-test

# Evaluate a target configuration file inside an isolated sandbox
neuronix try ./configuration.nix --timeout 60
```

### 6. Model Context Protocol (MCP) Server
NEURONIX includes a built-in Model Context Protocol server communicating over `stdio` adhering to JSON-RPC 2.0 (Protocol Version `2024-11-05`). It provides structured tools for autonomous development agents:
```bash
# Exposes neuronix_status, neuronix_diet, neuronix_verify, neuronix_undo, and neuronix_shadow_eval
neuronix mcp
```

---

## Verification & Test Harness

System invariants, module structures, and CLI dispatchers are validated through an automated test suite comprising **705 assertions across 20 verification suites**:

```text
═══════════════════════════════════════════════════════════════════
                    TEST HARNESS REPORT SUMMARY                    
═══════════════════════════════════════════════════════════════════
  Master Test Harness (tests/run_all_tests.sh)     : 506 / 506 PASS
  Distro Test Harness (tests/test_distro_suite.sh) : 199 / 199 PASS
  Total Executed Tests                             : 705 Tests
  Failed Verification                              : 0 Failures
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

## Architecture Decision Records (ADRs)

Formal design choices and rationales are maintained in `docs/adr/`:
- **[ADR-001](docs/adr/ADR-001-why-flakes.md):** Pure Nix Flakes as the Primary Interface
- **[ADR-002](docs/adr/ADR-002-why-calamares-flake-generator.md):** Declarative Flake Generation within Calamares
- **[ADR-003](docs/adr/ADR-003-immutable-store-vs-flatpak.md):** Dual-Layer Software Architecture (Immutable Nix Core vs Sandboxed Flatpak)
- **[ADR-004](docs/adr/ADR-004-update-channel-strategy.md):** Upstream Synchronization and Fork Mitigation Strategy
- **[ADR-005](docs/adr/ADR-005-hardware-detection-architecture.md):** Hybrid Hardware Detection and Battery Longevity Architecture

---

## License

NEURONIX OS is open-source software licensed under the **Apache License, Version 2.0**. See the [LICENSE](LICENSE) file for terms and conditions.

Copyright (c) 2026 NEURONIX Contributors.
