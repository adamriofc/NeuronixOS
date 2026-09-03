# NEURONIX Specification: Implementation Roadmap & Phased Execution

> **Document ID:** `NRX-ROAD-004`  
> **Status:** APPROVED  
> **Path:** `docs/specifications/04_IMPLEMENTATION_ROADMAP.md`  

---

## 1. Phased Execution Methodology

To ensure systematic software engineering, development of the NEURONIX platform progressed through 5 phased stages:

```text
┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   PHASE 0    │ ──► │   PHASE 1    │ ──► │   PHASE 2    │ ──► │   PHASE 3    │ ──► │   PHASE 4    │
│  Foundations │     │   Core MVP   │     │ MCP Server   │     │  Shadow VM   │     │ Standalone OS│
│  Workspace   │     │  CLI v0.1    │     │ JSON-RPC 2.0 │     │ Canary v0.3  │     │ ISO Distro   │
└──────────────┘     └──────────────┘     └──────────────┘     └──────────────┘     └──────────────┘
```

---

## 2. Phase Breakdown

### PHASE 0: Project Inception & Standards
- **Key Objectives:**
  1. Initialize Git repository with structured module layout: `src/`, `modules/`, `installer/`, `packages/`, `tests/`, `docs/`.
  2. Establish `Apache-2.0` license and standardized technical documentation.
  3. Configure strict `.gitignore` patterns preventing binary leaks and ephemeral state tracking.
- **Exit Gate 0:** Clean repository structure with hermetic configuration anchors.

---

### PHASE 1: Core CLI Guardian Engine (MVP - v0.1)
- **Key Capabilities:**
  1. **`neuronix status`:** Terminal dashboard displaying generation version, storage utilization, and systemd timer health.
  2. **`neuronix diet`:** Orchestrates `nix-collect-garbage -d`, store hardlink optimization, and issues `fstrim -av` to host storage.
  3. **`neuronix run <app>`:** Provisions isolated subshells via `nix-shell` with immediate cleanup upon exit.
  4. **`neuronix undo`:** Executes atomic system rollback to the preceding generation in under 2 seconds.
- **Exit Gate 1:** Verified storage reclamation, zero-garbage subshell exit, and deterministic rollback behavior.

---

### PHASE 2: Model Context Protocol (MCP) Server (v0.2)
- **Key Capabilities:**
  1. Implements JSON-RPC 2.0 Model Context Protocol over `stdio`.
  2. Exposes structured tools: `neuronix_status`, `neuronix_diet`, `neuronix_verify`, and `neuronix_undo`.
  3. Provides machine-readable interfaces for autonomous agents and IDEs.
- **Exit Gate 2:** Strict JSON-RPC 2.0 protocol compliance validated against protocol test batteries.

---

### PHASE 3: Ephemeral Micro-VM Simulation (v0.3)
- **Key Capabilities:**
  1. **`neuronix try`:** Spawns an ephemeral QEMU micro-VM directly in RAM (`/dev/shm`).
  2. Connects to `/nix/store` via read-only 9P filesystem mounts.
  3. Allows dry-testing experimental configurations and kernel options without modifying host state.
- **Exit Gate 3:** Fast micro-VM boot lifecycle with zero host state corruption.

---

### PHASE 4: Standalone Operating System Distribution (v1.0)
- **Key Capabilities:**
  1. **Live ISO Image:** Bootable hybrid UEFI/BIOS ISO installer with offline firmware bundles.
  2. **Declarative Calamares Installer:** Custom Calamares workflow generating target `flake.nix` configurations and Btrfs ZSTD:3 subvolumes.
  3. **Hardware Compatibility Matrix:** 27 declarative subsystem profiles (NVIDIA PRIME, PipeWire LDAC/LC3Plus, S0ix power, 80% battery threshold).
  4. **NEURONIX Center (`neuronix-center`):** Graphical control center and rollback hub.
  5. **Developer Toolchains (`neuronix dev`):** Hermetic stacks for Python, Rust, Node.js, AI/ML, Go, and Web3.
- **Exit Gate 4:** 705 automated test assertions passing with 100% success rate across master and distro harnesses.
