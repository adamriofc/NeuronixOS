# NEURONIX OS: Reference Hardware Qualification Matrix

> **Document ID:** `NRX-HW-001`  
> **Target Release:** `v1.0.3`  
> **Status:** APPROVED  
> **Specification Path:** `docs/hardware_profiles.md`  

---

## 1. Architectural Scope

NEURONIX OS defines 27 declarative hardware and subsystem configuration controls across CPU microcode, graphical offloading, storage, audio, power management, and memory pressure. To provide empirical grounding beyond configuration intent, this matrix documents qualification status across representative reference architectures.

---

## 2. Reference Hardware Qualification Matrix

| Reference Platform | Processor / Architecture | GPU Subsystem | Wi-Fi / Bluetooth | Audio Duplex | Suspend / S3 | Qualification Tier |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Generic QEMU / KVM Micro-VM** | Virtual x86_64 (KVM Host) | VirtIO-GPU / DRM | VirtIO-Net | PipeWire Dummy | S3 / S4 Supported | **Tier 1 (CI Validated)** |
| **Lenovo ThinkPad T14 / P14s (Gen 4/5)** | AMD Ryzen 7 PRO (Zen 4) | AMD Radeon 780M (Mesa RDNA3) | Qualcomm Atheros / MT7922 | Realtek ALC257 (PipeWire) | Deep (`mem_sleep=deep`) | **Tier 1 (Target Reference)** |
| **Framework Laptop 13 (Intel Core Ultra)** | Intel Core Ultra 7 155H | Intel Arc Graphics (Xe-LPG) | Intel Wi-Fi 6E AX211 | Realtek ALC295 (PipeWire) | Modern Standby (s2idle) | **Tier 1 (Target Reference)** |
| **Custom AMD Workstation (Ryzen + RDNA3)** | AMD Ryzen 9 7950X (Zen 4) | AMD Radeon RX 7900 XTX (Mesa RADV) | Intel I225-V 2.5GbE / AX210 | Realtek ALC4080 (PipeWire) | S3 Sleep Supported | **Tier 1 (Desktop Reference)** |
| **Intel Desktop Workstation (Core + Arc)** | Intel Core i7-14700K (Raptor Lake) | Intel Arc A770 / UHD Graphics 770 | Realtek RTL8125 2.5GbE / AX211 | Realtek ALC1220 (PipeWire) | S3 Sleep Supported | **Tier 1 (Desktop Reference)** |
| **Dell XPS 15 / 16 (Hybrid Dual-GPU)** | Intel Core i7/i9 (Alder/Raptor Lake) | Intel Iris Xe + NVIDIA RTX 4060 | Killer Wi-Fi 6E AX1675 | Realtek ALC3281 (PipeWire) | Modern Standby (s2idle) | **Tier 2 (PRIME Offload Validated)** |
| **ASUS ROG Zephyrus G14 (AMD + NVIDIA)** | AMD Ryzen 9 + NVIDIA RTX 4060 | AMD Radeon 780M + RTX 4060 Mobile | MediaTek MT7922 Wi-Fi 6E | Realtek HD Audio (PipeWire) | Deep (`mem_sleep=deep`) | **Tier 2 (Hybrid PRIME Qualified)** |
| **Apple Silicon (aarch64 via UTM / Asahi)** | Apple M1/M2/M3 (aarch64) | Apple AGX / VirtIO-GPU | Broadcom Wi-Fi / VirtIO | PipeWire Core | Suspend Supported | **Tier 2 (Experimental aarch64)** |

---

## 3. Qualification Tiers Defined

1. **Tier 1 (CI & Target Reference):**
   - Automated continuous evaluation in GitHub Actions CI via headless QEMU micro-VMs.
   - Core baseline for Calamares automated installation, Btrfs subvolumes, systemd-boot, ZRAM memory compression, and NetworkManager.
   - Officially targeted by the NEURONIX core maintainers.

2. **Tier 2 (Ecosystem Qualified):**
   - Requires vendor-specific firmware or proprietary driver options (e.g. `neuronix.hardware.nvidia.enable = true;`).
   - Dual-GPU switching verified via `prime-run` offload directives (`nvidia-offload`).
   - Experimental architectures such as `aarch64-linux` evaluating standard NixOS arm64 closures.

---

## 4. Hardware Configuration Declarations (27 Pillars)

Hardware configurations in NEURONIX are managed through composable NixOS modules located in `modules/hardware/` and declarative substrate options, grouped into 27 configuration pillars (machine-readable taxonomy: `data/hardware_qualification.json`):
1. **CPU Subsystem:** Intel microcode patching, AMD Zen microcode patching.
2. **Graphics Offload:** AMDGPU Mesa RADV Vulkan, Intel Arc ANV/Xe driver, NVIDIA PRIME offload, NVIDIA Wayland synchronization.
3. **Memory Pressure Shield:** ZRAM ZSTD compressed swap, systemd-oomd memory monitor, PSI stall-rate monitoring and max_map_count tuning.
4. **Storage Architecture:** Btrfs automated subvolume layout, continuous async TRIM and weekly fstrim timer, EXT4 fallback support.
5. **Audio Subsystem:** PipeWire real-time duplex server, WirePlumber endpoint rules, Bluetooth high-definition codecs (LDAC, AptX HD, LC3).
6. **Networking:** NetworkManager declarative stack, systemd-resolved DNSSEC resolver, nftables default-drop ingress firewall.
7. **Power Management:** Battery longevity charge ceiling (80%), thermald dynamic throttling prevention, TLP power governor profiles.
8. **Boot Architecture:** systemd-boot EFI manager, local RTC dual-boot synchronization, selectable Linux kernel flavor profiles.
9. **Platform Security:** Lanzaboote UEFI Secure Boot signing, TPM2 device enrollment and LUKS unlocking, AppArmor sandbox profiles.

---

## 5. Machine-Readable Verification Evidence

To ensure continuous transparency, qualification statuses and configuration pillars are exported programmatically:
- **Canonical Schema:** [data/hardware_qualification.json](../data/hardware_qualification.json)
- **Multi-Arch Evaluation Suite:** [tests/test_multiarch_matrix.sh](../tests/test_multiarch_matrix.sh)
- **E2E Lifecycle Evidence:** [dist/e2e_evidence.json](../dist/e2e_evidence.json)
