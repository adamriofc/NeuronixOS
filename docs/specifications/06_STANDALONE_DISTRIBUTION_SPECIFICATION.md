# NEURONIX Specification: Standalone Operating System Distribution (Phase 4)

> **Document Code:** `06_DISTRO_SPEC`  
> **Version:** 1.0.0-RELEASE  
> **Status:** Approved Architecture Specification  
> **Components:** Standalone Bootable ISO, Calamares Installer, Wayland Desktop Suites, & Control Center  

---

## 1. Positioning & 4-Layer Platform Architecture

### Official Positioning Statement
> **"A declarative, reproducible Linux distribution built on NixOS, engineered to deliver an automated graphical installation workflow, integrated hardware profiles, graphical system management, and atomic generation rollbacks, while strictly preserving NixOS's declarative and reproducible architecture."**

NEURONIX is an independent operating system distribution platform providing deep systems integration:

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

---

## 2. Graphical Calamares Installation Architecture

Calamares is integrated declaratively within `hosts/iso/default.nix`:

```text
┌──────────────────────────────────────────────────────────────┐
│                    CALAMARES INSTALLATION FLOW               │
├──────────────────────────────────────────────────────────────┤
│ 1. Boot Live ISO (Standard Open-Source or NVIDIA Driver)     │
│ 2. Select Language, Keyboard, and Regional Timezone          │
│ 3. Partitioning: Btrfs Subvolumes with ZSTD:3 Compression    │
│ 4. Desktop Environment Selection (KDE 6, GNOME, Hyprland)    │
│ 5. User Account Setup & Security Credentials                 │
│ 6. Declarative nixos-install Execution                       │
│ 7. Reboot into Target System                                 │
└──────────────────────────────────────────────────────────────┘
```

### Btrfs Subvolume Topology
The installation engine partitions storage utilizing a standardized Btrfs layout:

| Subvolume | Mount Point | Options | Purpose |
| :--- | :--- | :--- | :--- |
| `@` | `/` | `compress=zstd:3,noatime,space_cache=v2` | Operating system root files and immutable configuration pointers. |
| `@nix` | `/nix` | `compress=zstd:3,noatime` | Deduplicated and compressed `/nix/store`. |
| `@home` | `/home` | `compress=zstd:3,noatime` | User data, projects, and personal dotfiles. |
| `@snapshots` | `/.snapshots` | `compress=zstd:3,noatime` | Storage repository for atomic filesystem snapshots. |
| `@swap` | `/swap` | `nodatacow,noatime` | Dedicated swapfile subvolume with Copy-on-Write disabled. |

---

## 3. Desktop Environment Configurations

NEURONIX packages three curated, pre-configured Wayland desktop environments:
1. **KDE Plasma 6 (Flagship):** Wayland native, SDDM display manager, Fractional Scaling with Wayland Ozone integration, and KDE Discover Flatpak backend.
2. **GNOME Wayland:** Tokyo Cyber styling, GDM display manager, and GNOME Software Flatpak backend.
3. **Hyprland:** Dynamic Waybar status panel, Kitty terminal, and pre-configured keybindings.

---

## 4. System Management Hub (`neuronix-center`)

A native administrative management utility providing:
- **Telemetry Dashboard:** Live monitoring of active generation, kernel release, CPU, GPU, and compression statistics.
- **Generation Management:** Graphical inspection and instantaneous rollback in under 2 seconds.
- **Storage Maintenance:** Direct controls for store garbage collection, deduplication, and filesystem TRIM.
- **Dual Execution Interface:** Supports both graphical desktop mode and headless terminal CLI mode (`--cli`).
