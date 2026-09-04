# NEURONIX Specification: Product Requirements Document (PRD)

> **Document ID:** `NRX-PRD-001`  
> **Status:** APPROVED  
> **Path:** `docs/specifications/01_PRD_PRODUCT_REQUIREMENTS.md`  

---

## 1. Vision & Objectives

### 1.1 Vision
Deliver an independent declarative operating system platform and developer execution environment that combines functional reproducibility with automated installation, integrated hardware profiles, and autonomous storage optimization.

### 1.2 Objectives
1. **Reduce Developer Environment Friction:** Provide on-demand, hermetic developer toolchains (`neuronix dev`) that run in memory without background daemons.
2. **Mitigate System Mutation Risks:** Ensure changes are evaluated via dry-build compiler checks and can be reverted in under 2 seconds.
3. **Automate Storage Maintenance:** Continuously optimize storage through in-kernel compression (ZSTD:3), deduplication, and scheduled host TRIM timers.
4. **Accessible Declarative Infrastructure:** Provide a graphical installation engine (Calamares) that outputs clean Nix flakes for immediate declarative management.

---

## 2. Problem Statement & Architecture Comparison

| Engineering Problem | Legacy Operating System State | NEURONIX Platform Solution |
| :--- | :--- | :--- |
| **Container Overhead** | Heavy background container runtimes consuming 4-8 GB RAM and accumulating unreferenced image layers. | **Daemonless Ephemeral Substrate:** In-memory `nix-shell` execution using content-addressed store hardlinks without background daemons. |
| **System Breakage from Untrusted Changes** | Imperative package managers mutating shared system directories, resulting in broken dependencies or unbootable states. | **Atomic State & 2-Second Rollback:** Every system generation is atomic; earlier generations can be restored instantly via `neuronix undo`. |
| **Virtual Disk Expansion** | Sparse disk images (`.qcow2` / `.vhdx`) expanding indefinitely without releasing deleted blocks to the host SSD. | **Automated TRIM Lifecycle:** Scheduled daily TRIM unmap signals pass through VirtIO/SCSI controllers to reclaim host physical storage. |
| **Declarative Learning Curve** | Complex syntax and fragmented documentation in functional package managers. | **Calamares Flake Generation:** Automated graphical onboarding that generates clean, human-readable flakes on target disks. |

---

## 3. Use Cases & Scenarios

### Scenario 1: Ephemeral Tool Execution
- **Context:** Running a utility or compiler without installing it globally.
- **Requirement:** `neuronix run <packages...>` provisions an isolated subshell in under 3 seconds with access to Wayland, audio, and network. All temporary paths are reclaimed upon session termination.

### Scenario 2: Isolated Development Toolchains
- **Context:** Working on multiple language ecosystems with conflicting dependencies.
- **Requirement:** `neuronix dev <python|rust|node|ai|go|web3>` provisions pre-configured development toolchains in RAM, isolated from the base system.

### Scenario 3: Autonomous Storage Pruning
- **Context:** Preventing storage ballooning and disk exhaustion over long operational lifetimes.
- **Requirement:** `neuronix diet` orchestrates store garbage collection, hardlink deduplication, and filesystem TRIM in a single command.

### Scenario 4: Ephemeral System Simulation
- **Context:** Testing experimental configuration files or packages before committing to host state.
- **Requirement:** `neuronix try [file.nix]` spins up an in-memory QEMU micro-VM with read-only 9P store sharing, verifying that the target evaluates cleanly.

---

## 4. Key Performance Indicators (KPIs)

| Metric | Target | Verification Method |
| :--- | :--- | :--- |
| Rollback Latency | < 2.0 seconds | Automated switch duration test |
| Dev Stack Provisioning | < 3.0 seconds | Dry-run shell evaluation |
| Storage Compression Ratio | 30% - 50% workload-dependent savings | Btrfs filesystem compsize audit |
| Test Suite Reliability | 100% pass (0 failures) | 854-assertion automated verification suite |
