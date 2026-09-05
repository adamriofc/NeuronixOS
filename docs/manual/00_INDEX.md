# NEURONIX OS Technical Manual & System Reference

**Distribution:** NEURONIX OS (Declarative Linux Platform)  
**Substrate:** Pure-Functional NixOS (Linux Kernel 6.18+ / nixos-26.05)  
**System Location:** `/etc/neuronix/manual/`  
**License:** Apache License 2.0  

---

## 1. Scope & Purpose

This manual is an immutable, system-embedded technical reference engineered for both human administrators and autonomous AI agents (such as OpenCode, Claude Desktop, Antigravity, and Cursor). It documents the complete operational lifecycle, declarative configuration contracts, filesystem topologies, sandbox execution mechanisms, and hardware enablement parameters of NEURONIX OS.

Because this manual is packaged directly into the NixOS system derivation, it automatically recompiles and synchronizes with every system upgrade (`nixos-rebuild switch` or `neuronix upgrade`).

---

## 2. Table of Contents

| File | Topic Title | Scope & Description |
| :--- | :--- | :--- |
| `01_ARCHITECTURE.md` | Platform Architecture | 4-layer model, Nix substrate, immutability, and P0-P4 proof class taxonomy. |
| `02_CONFIGURATION_REFERENCE.md` | Declarative Configuration | Complete `neuronix.*` options, declarative package management, and distro transition guide. |
| `03_CLI_REFERENCE.md` | Unified CLI Manual | Comprehensive syntax, options, and exit codes for all 18 `neuronix` commands. |
| `04_STORAGE_AND_ROLLBACK.md` | Storage & Rollback Engine | Btrfs 5-subvolume topology, ZSTD compression, atomic rollbacks, GC, and TRIM. |
| `05_SHADOW_VM_AND_SANDBOX.md` | Shadow Micro-VM Simulation | In-memory RAM Micro-VMs (`/dev/shm`), smoke testing, and zero blast radius execution. |
| `06_DEVELOPER_STACKS.md` | Hermetic Dev Stacks | Isolated toolchains (Python, Rust, Node, AI, Go, Web3) and JSON manifest synthesis. |
| `07_MCP_PROTOCOL_AND_AI_GATEWAY.md` | Model Context Protocol | JSON-RPC 2.0 stdio server, tool definitions, flock concurrency, and client setup. |
| `08_HARDWARE_AND_27_PILLARS.md` | Hardware & 27 Pillars | 8 Reference Platforms, 27 configuration pillars, NVIDIA PRIME, and ZRAM PSI shield. |
| `09_SECURITY_AND_ATTESTATION.md` | Security & Supply Chain | Privilege allowlists, regex filtering, Secure Boot, TPM2, and SPDX 2.3 SBOM. |
| `10_AI_AGENT_REFERENCE.md` | AI Copilot System Directive | High-density semantic reference, operating rules, and guardrails for AI models. |

---

## 3. Quick Navigation Commands

Access this manual anytime directly from the terminal:

```bash
# View topic index
neuronix manual

# View specific chapter
neuronix manual arch
neuronix manual config
neuronix manual cli
neuronix manual storage
neuronix manual shadow
neuronix manual dev
neuronix manual mcp
neuronix manual hardware
neuronix manual security
neuronix manual ai

# Stream manual via MCP JSON-RPC protocol
echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"neuronix_manual","arguments":{"topic":"storage"}}}' | neuronix mcp
```
