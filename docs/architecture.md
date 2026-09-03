# Arsitektur Teknis Sistem Operasi NEURONIX

Dokumen ini menjelaskan arsitektur 4-Layer Platform yang mendasari distribusi mandiri NEURONIX.

## 1. Diagram 4-Layer Platform Architecture

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

## 2. Struktur Modul Deklaratif (`modules/`)
1. **Core:** `nix-ld` bawaan, `allowUnfree = true`, terminal sadar generasi.
2. **Hardware:** Deteksi firmware offline, NVIDIA PRIME, manajemen daya S0ix, PipeWire audio HD duplex, bootloader limit 15 generasi di ESP 1.0 GiB.
3. **Services:** Active Memory Pressure Shield (ZRAM ZSTD + systemd-oomd), Btrfs balance timer, Flatpak Flathub marketplace, NetworkManager captive portal detection, AirPrint & Mopria IPP driverless printing.
4. **Desktop:** KDE Plasma 6 Wayland, GNOME Wayland (Tokyo Cyber), Hyprland auto-tiling.

## 3. Matriks 27 Pilar Pertahanan Perangkat Keras
Seluruh 27 pilar diintegrasikan secara deklaratif untuk menjamin kebal terhadap kegagalan hardware laptop, desinkronisasi jam dual-boot dengan Windows, dan OOM lockup.
