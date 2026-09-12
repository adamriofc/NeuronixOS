# NEURONIX Specification: Hardware Qualification Matrix & L5 Real Hypervisor Verification Contract

> **Document ID:** `NRX-SPEC-022`  
> **Version:** 1.0.5-RELEASE  
> **Status:** Ratified & Active  
> **Subsystem:** Hardware Qualification, Platform Telemetry, and Physical Execution Gates  
> **Verification Gate:** `tests/e2e/test_hardware_contracts.sh` & `tests/e2e/real/test_real_os_install_boot.sh`  

---

## 1. Executive Summary & Epistemic Honesty Doctrine

In distributed systems and operating system distribution qualification, a fundamental distinction exists between **portable software contracts** and **physical bare-metal execution guarantees**:

1. **L4 Hybrid Engine Contract (Fully Verified in CI):** Evaluates derivation evaluation, pure-functional NixOS building, Calamares dual-plane installer logic, direct disk formatting semantics, sparse partitioning, AST validation, and atomic profile symlink swapping. This contract executes deterministically in continuous integration environments without requiring bare-metal host hypervisor access.
2. **L5 Real Hypervisor E2E Qualification (Truthfully Reserved for Bare-Metal & KVM Hosts):** Verifies real hardware-accelerated QEMU/KVM virtual machine instantiation, guest UEFI boot loader interaction, disk block passthrough, and guest-to-host multi-hop rollback verification.

NEURONIX OS enforces a strict **Zero-Simulation Policy**: when continuous integration or containerized test runners lack hardware virtualization acceleration (`/dev/kvm`), NEURONIX **never fakes or simulates L5 execution**. Instead, execution is truthfully recorded as an L4 verification contract, preserving 100% epistemic honesty across all release qualification reports.

---

## 2. Proof Class Taxonomy (L0 through L5)

| Proof Class | Verification Scope | Execution Environment | Release Gate Policy |
| :--- | :--- | :--- | :--- |
| **`L0_STATIC`** | Static syntax, AST validation, markdown contracts, flake structure, and lint invariants. | Any POSIX shell | Mandatory Release Blocker |
| **`L1_UNIT`** | Fast deterministic unit tests, pure-Python cryptography, argument fuzzing, and schema bounds. | Local developer environment & CI | Mandatory Release Blocker |
| **`L2_SYSTEM`** | Service state machines, socket activation, Conductor IPC, and transaction logging. | Linux system with tmpfs / cgroups | Mandatory Release Blocker |
| **`L3_REPRODUCIBILITY`** | Bit-identical store derivations, NAR hashing, and multi-build reproducibility. | Linux host with Nix daemon | Mandatory Release Blocker |
| **`L4_HYBRID_ENGINE`** | Installer engine, direct formatting, atomic rollback progression, and benchmark latency gates. | Continuous integration pipelines | Mandatory Release Blocker |
| **`L5_REAL_E2E`** | Real hardware-accelerated QEMU/KVM OS installation, sparse target partitioning, and multi-boot qualification. | Dedicated physical bare-metal runner with RW KVM | Truthfully Reserved (Non-simulated) |

---

## 3. Mandatory L5 Hardware Execution Prerequisites

When the L5 verification gate is invoked with `--require-l5`, the verification runner (`tests/e2e/real/test_real_os_install_boot.sh`) evaluates five strict physical prerequisites:

```text
                        L5 PREREQUISITE EVALUATION PIPELINE
                                         │
        ┌────────────────────────────────┼────────────────────────────────┐
        ▼                                ▼                                ▼
1. /dev/kvm Access              2. CPU Hardware Virtualization     3. Host Memory Headroom
   (RW character node)             (Intel VT-x 'vmx' or AMD-V 'svm')   (>= 4 GiB unreserved RAM)
        │                                │                                │
        └────────────────────────────────┼────────────────────────────────┘
                                         ▼
                        ┌────────────────────────────────┐
                        ▼                                ▼
                4. Block Storage Headroom       5. Staged Live ISO Image
                   (>= 15 GiB dedicated raw)       (neuronix-os-1.0.5-x86_64.iso)
```

1. **Character Node Access:** `/dev/kvm` must exist and be writable by the invoking UID (`test -w /dev/kvm`).
2. **CPU Virtualization Extensions:** Host `/proc/cpuinfo` must advertise either `vmx` (Intel Virtualization Technology) or `svm` (AMD Secure Virtual Machine).
3. **Host Memory Headroom:** Available physical RAM must be $\ge 4\text{ GiB}$ to provision guest memory without invoking the Linux OOM-killer.
4. **Block Storage Headroom:** Target storage directory must provide $\ge 15\text{ GiB}$ free space to house the sparse virtual disk image and installation target.
5. **Staged Live ISO:** Official bootable ISO (`dist/neuronix-os-1.0.5-x86_64.iso`) must be present with validated SHA-256 integrity.

If any prerequisite is unsatisfied, execution cleanly and truthfully defers with an explicit diagnostic reason code (`L5_HARDWARE_PREREQUISITES_MISSING`), documenting the exact missing parameter without emitting false failure or fraudulent pass claims.

---

## 4. Hardware Qualification Matrix

Platforms targeted and qualified by NEURONIX OS are categorized into five rigorous tiers in `data/hardware_qualification.json`:

```text
BARE_METAL_TESTED   -> Physically executed, observed, and benchmarked on maintainer reference hardware.
VM_VALIDATED        -> Physically validated under virtualized hypervisor execution (QEMU/KVM).
CI_VALIDATED        -> Automated evaluation and test execution passing in continuous integration pipelines.
TARGET              -> Hardware platform targeted with dedicated declarative modules in modules/hardware.
EXPERIMENTAL        -> Community or exploratory architectures without tier-1 release guarantees.
```

### 4.1 Tier 1 Reference Platforms

| Platform ID | Hardware Description | Architecture | Qualification Level | Validation Method |
| :--- | :--- | :---: | :---: | :--- |
| **`amd-workstation-rdna3`** | AMD Ryzen 9 7950X, Radeon RX 7900 XTX (Mesa RADV), Intel I225-V 2.5GbE, Realtek ALC4080 PipeWire | `x86_64` | `BARE_METAL_TESTED` | Maintainer Physical Hardware Benchmark & Workstation Test |
| **`qemu-kvm-microvm`** | Generic QEMU / KVM Micro-VM (Host Passthrough, VirtIO-GPU, VirtIO-Net) | `x86_64` | `VM_VALIDATED` | Dual-Mode E2E Runner + GitHub Actions CI |
| **`lenovo-thinkpad-t14`** | Lenovo ThinkPad T14 / P14s (Gen 4/5, AMD Ryzen 7 PRO, Radeon 780M) | `x86_64` | `TARGET` | Declarative Profile (`modules/hardware/lenovo-thinkpad.nix`) |
| **`framework-laptop-13`** | Framework Laptop 13 (Intel Core Ultra 7 155H Meteor Lake, Arc Graphics) | `x86_64` | `TARGET` | Declarative Profile (`modules/hardware/framework-13.nix`) |
| **`intel-workstation-arc`** | Intel Core i7-14700K Raptor Lake, Intel Arc A770, RTL8125 2.5GbE | `x86_64` | `TARGET` | Declarative Profile (`modules/hardware/intel-arc.nix`) |
| **`dell-xps-15-hybrid`** | Dell XPS 15 / 16 (Intel Core i7/i9, NVIDIA RTX 4060 Mobile PRIME) | `x86_64` | `TARGET` | Declarative PRIME Profile (`modules/hardware/nvidia-prime.nix`) |

---

## 5. Automated Hardware Contract Suite

Automated verification of hardware contracts is executed via `tests/e2e/test_hardware_contracts.sh` across seven critical dimensions:
1. **CPU & Topology Detection:** Verifies that `neuronix_core.telemetry` extracts valid CPU topology metrics without hardcoded strings.
2. **Memory Telemetry Contract:** Validates positive host RAM detection and dynamic memory pressure telemetry.
3. **ZRAM Swap Module:** Ensures declarative `zstd` compression algorithm and 100% memory allocation ceiling in `modules/services/memory-shield.nix`.
4. **Storage Auto-TRIM:** Verifies declarative `services.fstrim` periodic block discard timers in `modules/services/storage.nix`.
5. **Btrfs Metadata Auto-Balance:** Confirms monthly automated Btrfs balance invocation to eliminate allocated unallocated chunk fragmentation.
6. **Flash Storage Journal Ceiling:** Confirms `SystemMaxUse=500M` limit in `systemd-journald` to prevent NAND flash block wear.
7. **Qualification Manifest Integrity:** Asserts structural schema validity and minimum platform coverage in `data/hardware_qualification.json`.
