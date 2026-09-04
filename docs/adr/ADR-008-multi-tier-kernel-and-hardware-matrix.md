# ADR-008: Declarative Multi-Tier Kernel Selection and Hardware Hardening Matrix

## Status
**Accepted** (Approved for NEURONIX OS Standalone Distribution)

## Context & Problem Statement
Workstations exhibit divergent operational requirements: low-latency interactive responsiveness for creative and developer workflows, enterprise long-term stability for production servers, or attack-surface minimization for security evaluation. Traditional distributions require complex repository swaps or manual kernel compilation, risking broken out-of-tree module dependencies (e.g., NVIDIA proprietary drivers, ZFS, v4l2loopback).

## Architectural Decision
NEURONIX provides a declarative kernel flavor configuration option (`neuronix.hardware.boot.kernelFlavor`):
- `zen`: Liquorix-tuned low-latency kernel scheduler optimized for desktop responsiveness and real-time audio/workstation tasks.
- `lts`: Long-Term Support kernel branch targeting enterprise stability and conservative driver compatibility.
- `hardened`: Linux-hardened kernel tree incorporating security mitigations, strict memory protection, and restricted kernel self-inspection.
- `default`: Upstream stable Nixpkgs kernel providing standard reference compatibility.
Coupled with this, NEURONIX deploys a 27-pillar hardware hardening matrix covering CPU microcode (Intel/AMD), NVIDIA PRIME dynamic render offload, and complete redistributable Wi-Fi/Bluetooth firmware blobs (`hardware.enableAllFirmware = true`).

## Consequences
- **Positive:** Switching kernels is a single-line declarative configuration change with instant bootloader selection; out-of-the-box hardware detection ensures functional Wi-Fi, graphics, and peripherals from first boot; zero manual out-of-tree module compilation.
- **Trade-off:** Proprietary kernel modules must maintain compatibility with the selected kernel branch, validated automatically via our CI test harness.
