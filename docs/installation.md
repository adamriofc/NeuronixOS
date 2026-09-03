# NEURONIX OS Installation Guide

## 1. System Requirements
- **Processor:** 64-bit x86_64 Dual-Core (Intel or AMD)
- **Memory (RAM):** Minimum 4 GB (8 GB+ recommended for compilation workflows and ZRAM ZSTD)
- **Storage:** Minimum 30 GB available space on SSD/NVMe (Automated Btrfs ZSTD:3 layout)
- **Display:** Minimum resolution 1024x768 (HiDPI / 4K scaling supported out-of-the-box)

## 2. Creating Bootable USB Media
Download the `neuronix-os-x86_64.iso` image file and flash it to a USB drive using one of the following methods:
- **Using dd on Linux:**
  ```bash
  sudo dd if=neuronix-os-x86_64.iso of=/dev/sdX bs=4M status=progress oflag=sync
  ```
- **Using Ventoy or BalenaEtcher:** Copy the ISO image directly to a Ventoy-formatted USB drive.

## 3. Calamares Installation Workflow
1. Boot the target system from the live USB media. Select `Standard Open-Source` or `NVIDIA Proprietary`.
2. On the Live Desktop, the Calamares Installer will launch automatically.
3. Configure regional language, timezone, and keyboard layout.
4. On the disk partition screen, select **Erase Disk** (automated Btrfs ZSTD:3 layout) or **Manual Partitioning**.
5. Set up user credentials and host password.
6. Click **Install**. The `neuronix-install-engine` will generate declarative Flake configurations and execute `nixos-install`.
7. Once installation completes, remove the USB drive and reboot into your new NEURONIX OS environment.
