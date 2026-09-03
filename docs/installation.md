# NEURONIX OS Installation Guide

> **Document ID:** `NRX-INST-001`  
> **Status:** APPROVED  
> **Scope:** Live Media Preparation, Calamares Partitioning, and First-Boot Verification  

---

## 1. System Requirements

Before installing NEURONIX OS, verify that target hardware satisfies the following hardware thresholds:

| Hardware Component | Minimum Requirement | Recommended Specification |
| :--- | :--- | :--- |
| **Processor (CPU)** | 64-bit x86_64 Dual-Core (Intel Core 2 / AMD Athlon 64 X2) | Modern Quad-Core or higher (Intel Core i5/i7/i9 or AMD Ryzen) |
| **System Memory (RAM)** | 4 GB physical RAM | 8 GB or 16 GB+ (allows in-RAM ZRAM compression and parallel compiling) |
| **Storage Capacity** | 30 GB SSD or NVMe storage | 64 GB+ NVMe SSD (enables multi-generation snapshot retention) |
| **Display Resolution** | 1024x768 display resolution | 1920x1080 (FHD) or 3840x2160 (4K UHD with Fractional Scaling) |
| **Firmware Interface** | UEFI 64-bit (CSM/Legacy BIOS supported via hybrid ISO) | Modern UEFI with Secure Boot disabled during installation |
| **Graphics Controller** | Intel HD Graphics / AMD Radeon / NVIDIA GeForce | Dedicated NVIDIA GPU (Optimus/PRIME offload) or AMD/Intel GPU |
| **Network Interface** | Ethernet or Wi-Fi (offline installation supported) | High-speed Wi-Fi or Gigabit Ethernet for initial package syncing |

---

## 2. Bootable USB Media Preparation

### A. Integrity Verification
Prior to flashing the bootable image, calculate and verify the cryptographic SHA256 checksum of the downloaded ISO:

```bash
sha256sum neuronix-os-x86_64.iso
```

Ensure the resulting digest matches the official checksum published on the GitHub Releases page.

### B. Flashing the Installation Media

#### Method 1: Using `dd` on Linux (Terminal)
Identify the block device identifier of your USB drive using `lsblk`. Replace `/dev/sdX` with your target drive (do not specify a partition like `/dev/sdX1`):

```bash
sudo dd if=neuronix-os-x86_64.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

#### Method 2: Using Ventoy (Multi-Boot USB)
If you utilize Ventoy, format the USB drive with Ventoy and copy `neuronix-os-x86_64.iso` directly into the Ventoy data partition.

#### Method 3: Graphical Flashing Tools
You may flash the ISO using cross-platform utilities such as BalenaEtcher or Raspberry Pi Imager.

---

## 3. Live Environment Boot Options

Insert the bootable USB media into the target machine and invoke the boot selection menu (commonly `F12`, `F11`, `F8`, or `Del`).

The systemd-boot loader presents two primary execution kernels:
1. **NEURONIX Live (Standard Open-Source):** Boots using open-source kernel graphics drivers (Mesa, Nouveau, Intel Iris, AMDGPU). Recommended for all systems without dedicated NVIDIA hardware.
2. **NEURONIX Live (NVIDIA Proprietary Drivers):** Boots with pre-packaged proprietary NVIDIA kernel modules. Recommended for laptops and workstations equipped with modern GeForce RTX, GTX, or Quadro graphics.

Both environments boot into a live user session (`neuronix`, passwordless sudo enabled).

---

## 4. Calamares Installation Workflow

The Calamares graphical installer initializes automatically upon reaching the live desktop environment.

```text
┌──────────────────────────────────────────────────────────────┐
│                    CALAMARES INSTALLATION FLOW               │
├──────────────────────────────────────────────────────────────┤
│ 1. Welcome Screen: Language and Regional Preference          │
│ 2. Location & Timezone: Geographic Locale Selection          │
│ 3. Keyboard Configuration: Layout and Variant Verification   │
│ 4. Partitioning Engine: Btrfs Subvolume Topology Selection   │
│ 5. User Creation: Primary User and Host Name Setup           │
│ 6. Installation Confirmation & Engine Execution              │
│ 7. Finalization: Clean Unmount and Reboot                    │
└──────────────────────────────────────────────────────────────┘
```

### Partitioning Strategies

#### Option A: Erase Disk (Automated Btrfs ZSTD:3 Topology - Recommended)
Selecting **Erase Disk** formats the storage drive and provisions a standardized Btrfs subvolume layout:
- **EFI System Partition (ESP):** 1.0 GiB formatted as FAT32, mounted at `/boot`.
- **Root Filesystem (`@`):** Formatted as Btrfs with ZSTD:3 transparent compression, mounted at `/`.
- **Nix Store Subvolume (`@nix`):** Dedicated subvolume for `/nix/store`, mounted at `/nix`.
- **User Data Subvolume (`@home`):** Dedicated subvolume for user directories, mounted at `/home`.
- **Snapshot Repository (`@snapshots`):** Subvolume allocated for system state rollbacks, mounted at `/.snapshots`.
- **Swap Subvolume (`@swap`):** Dedicated subvolume mounted at `/swap` with Copy-on-Write (CoW) disabled.

#### Option B: Manual Partitioning (Advanced / Dual-Boot)
If installing alongside Microsoft Windows:
1. Preserve the existing EFI System Partition (or expand it to at least 512 MB).
2. Create an unformatted partition of at least 30 GB.
3. Format the target partition as Btrfs and assign subvolumes `@`, `@nix`, and `@home`.
4. The installation engine will automatically enable Windows dual-boot clock synchronization (`time.hardwareClockInLocalTime = true`).

---

## 5. First-Boot System Verification

After completing installation, reboot the machine and remove the installation media. Log into your account and open a terminal to verify system status:

### 1. Inspect System Telemetry
```bash
neuronix status
```
This displays the active system generation, storage utilization, and systemd service status.

### 2. Launch the Graphical Control Center
```bash
neuronix-center
```
Use the control center to inspect hardware specifications, monitor memory usage, and access rollback history.

### 3. Initialize Developer Stacks
To provision an isolated developer toolchain without altering system configuration, execute:
```bash
neuronix dev python   # Launches Python 3.12, uv, Ruff, and Pyright
neuronix dev rust     # Launches Rustc, Cargo, rust-analyzer, and Clippy
neuronix dev node     # Launches Node.js 20 LTS, pnpm, and TypeScript
```

---

## 6. System Recovery & Rollback Procedures

### Instantaneous Rollback via CLI
If a newly applied configuration or package introduces an anomaly, roll back instantaneously to the preceding generation:
```bash
neuronix undo
```
The pointer symlink swaps in under 2 seconds without requiring a reboot for user-space changes.

### Rollback via Bootloader Menu
If the system encounters an unbootable state following a kernel update:
1. Power cycle the system and hold `Space` or `Esc` during UEFI initialization to display the systemd-boot menu.
2. Select a prior working generation (e.g., `Generation 14`).
3. Press `Enter` to boot directly into the immutable closure of that generation.
4. Once booted, activate the generation permanently using `neuronix undo`.
