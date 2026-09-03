# NEURONIX OS Technical Architecture

This document describes the 4-Layer Platform architecture powering the standalone NEURONIX distribution.

## 1. 4-Layer Platform Architecture Diagram

```text
                             NEURONIX PLATFORM
                                     │
      ┌──────────────────────────────┴──────────────────────────────┐
      │                                                             │
  UX LAYER                                                     SYSTEM LAYER
      │                                                             │
 • Calamares Installer (Flake-Generating)                      • NixOS Pure Substrate
 • NEURONIX Control Center (GUI System Center)                 • Declarative Flakes
 • First-Boot Welcome App & Hardware Profiler                  • Content-Addressed Store
 • Dual-Layer Software Marketplace (Flatpak)                   • Atomic Generations & Rollback
 • One-Click Developer Stacks (neuronix dev)                   • nix-ld Global Dynamic Loader
      │                                                             │
      └──────────────────────────────┬──────────────────────────────┘
                                     │
                           INFRASTRUCTURE LAYER
                                     │
                 • Hermetic ISO Image Compilation
                 • Automated CI/CD Headless QEMU VM Testing
                 • Automated Installer & Desktop Smoke Tests
                 • Hardware Driver Matrix (NVIDIA/PRIME/Wi-Fi)
                 • Architecture Decision Records (ADR-001 - 005)
```

## 2. Declarative Module Structure (`modules/`)
1. **Core:** Built-in `nix-ld` dynamic loader, unfree package allowance (`allowUnfree = true`), and generation-aware shell prompts.
2. **Hardware:** Offline firmware detection, NVIDIA PRIME dynamic offload, S0ix Modern Standby sleep management, PipeWire low-latency HD audio codecs, and EFI System Partition threshold limits (15 generations on 1.0 GiB ESP).
3. **Services:** Active Memory Pressure Shield (ZRAM ZSTD + systemd-oomd), monthly Btrfs balance timer, Flathub Flatpak application marketplace, NetworkManager captive portal detection, and IPP driverless printing (AirPrint & Mopria).
4. **Desktop:** KDE Plasma 6 Wayland, GNOME Wayland, and Hyprland auto-tiling window manager.

## 3. Hardware Compatibility Matrix
All hardware profiles are integrated declaratively to ensure resilience against mobile battery degradation, dual-boot Windows RTC clock desynchronization, and memory pressure lockups.
