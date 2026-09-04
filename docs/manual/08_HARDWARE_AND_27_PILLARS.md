# Chapter 8: Hardware Enablement & 27 Configuration Pillars

## 1. 8 Qualified Reference Platforms

NEURONIX OS maintains empirical hardware qualification across 8 reference workstation classes:

1. **Lenovo ThinkPad T14 / P14s (AMD Ryzen Pro):** Tier-1 reference laptop. S3 sleep, TrackPoint, battery threshold, thermal fan curves.
2. **Framework Laptop 13 / 16 (Intel Core Ultra & AMD 7040):** Tier-1 modular workstation. Expansion cards, ambient light sensor, fingerprint reader.
3. **Custom Desktop Workstation (AMD Ryzen 9 & Radeon RX 7000):** Tier-1 development desktop. Mesa RADV Vulkan, Resizable BAR, IOMMU PCIe passthrough.
4. **Custom Desktop Workstation (Intel Core 14th Gen & Arc A770):** Tier-1 Intel platform. Mesa ANV, Xe kernel driver, QuickSync video encoding.
5. **Dell XPS 15 / 17 (NVIDIA Hybrid Graphics):** Tier-2 mobile workstation. NVIDIA PRIME Render Offload, dynamic power management.
6. **ASUS ROG Zephyrus G14 (AMD + NVIDIA RTX):** Tier-2 gaming and compute laptop. ROG asusctl daemon, dGPU power cut in hybrid mode.
7. **Apple Silicon Mac (M1/M2 - aarch64-linux):** Tier-2 ARM reference. Asahi Linux kernel patches, Rust DRM GPU driver, NVMe controller.
8. **Headless Cloud / Micro-VM (QEMU / KVM / Proxmox):** Tier-1 CI & server substrate. VirtIO-net, VirtIO-scsi, 9P shared store, serial console.

---

## 2. The 27 Hardware Configuration Pillars

Hardware compatibility in NEURONIX is organized into 9 subsystems across 27 distinct configuration pillars:

* **Processor & Microcode:** AMD Microcode updates, Intel Microcode updates, CPU frequency scaling governor (`powersave` / `schedutil`).
* **Graphics & Display Pipelines:** AMDGPU Mesa RADV, Intel Xe/i915 Mesa ANV, NVIDIA Turing/Ampere/Ada driver with PRIME offload.
* **Storage Controllers:** NVMe autonomous power state transitions, AHCI SATA trim, Removable UDisks2 automount.
* **Audio Subsystem:** PipeWire HD duplex graph, WirePlumber session routing, Bluetooth LDAC and AptX-HD codecs.
* **Networking & Wireless:** NetworkManager backend, captive portal detection, Wi-Fi 6E/7 power saving.
* **Memory & Swap Shield:** ZRAM compressed in-memory swap pool (ZSTD), Linux kernel Pressure Stall Information (PSI) monitoring, systemd-oomd pressure kills.
* **Chassis & Power Policies:** ACPI power profiles daemon, laptop battery charging ceiling (80% longevity threshold), S2idle/Deep sleep states.
* **Boot Architecture:** systemd-boot EFI manager, local RTC dual-boot synchronization, selectable Linux kernel flavor profiles.
* **Platform Security:** Lanzaboote UEFI Secure Boot signing, TPM2 device enrollment and LUKS unlocking, AppArmor sandbox profiles.
