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

## 4. Hardware Configuration Declarations

Hardware configurations in NEURONIX are managed through composable NixOS modules located in `modules/hardware/`:
- `modules/hardware/boot.nix`: EFI systemd-boot loader, local RTC clock synchronization for Windows dual-booting.
- `modules/hardware/cpu.nix`: Automatic Intel and AMD microcode patching.
- `modules/hardware/nvidia-prime.nix`: Dual-GPU PRIME render offload with explicit PCI bus IDs.
- `modules/hardware/power.nix`: Charge ceilings for battery longevity (`charge_control_end_threshold`) and thermald CPU throttling prevention.
- `modules/hardware/audio.nix`: PipeWire low-latency duplex daemon, WirePlumber session management, and high-definition Bluetooth codecs (LDAC, AptX HD, LC3Plus).
- `modules/hardware/secureboot.nix`: Lanzaboote UEFI Secure Boot signing scaffolding with TPM2 integration.
