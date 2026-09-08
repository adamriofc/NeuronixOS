# ADR-011: Hyperion Provable Adaptive Execution Architecture (PAEA)

## Status
**Accepted** (Codified in NIP-0003 for NEURONIX OS Standalone Distribution)

## Context & Problem Statement
Traditional operating systems execute all user applications through a monolithic userspace-to-kernel mediation path. Developers and AI coding agents are forced to make a binary choice between running untrusted code on the host with zero blast-radius protection, or enduring the severe latency and resource overhead of heavyweight virtual machines. Furthermore, dynamic execution lacks cryptographic binding: after a build completes, the system cannot mathematically prove that it executed under declared isolation and network constraints.

## Architectural Decision
NEURONIX establishes **Project Hyperion (Provable Adaptive Execution Architecture - PAEA)** as the adaptive workload execution plane:
1. **Adaptive Isolation Ladder (Tier 0 to Tier 3):** Dispatches workloads dynamically to the minimum sufficient isolation tier: Tier 0 (Direct Silicon Fast-Path), Tier 1 (Ephemeral RAM Ghost via Bubblewrap in /dev/shm), Tier 2 (Hardened eBPF LSM Container Enclave), or Tier 3 (In-Memory Micro-VM via KVM).
2. **Hyperion Domain Specification (HDS v1.0.0):** Workloads declare resource envelopes (CPU, RAM, GPU, storage, network) and security contracts via RFC 8785 Canonical JSON contracts.
3. **Deterministic Safety Gatekeeper:** Enforces strict compile-time verification rejecting dangerous filesystem paths (`/etc/shadow`, `/root`, SSH/GPG keys) and unbounded resource allocations before execution.
4. **Merkle Domain Proof (MDP):** Binds workload execution output cryptographically to the host's 5-leaf Merkle StateRoot (`neuronix state`) and eBPF policy envelope.
5. **Unified Interfaces:** Exposes `neuronix run` for daily execution and `neuronix hyperion` for domain lifecycle and proof audits, backed by native Model Context Protocol (MCP) tooling for AI assistants.

## Consequences
- **Positive:** Eliminates developer friction by automatically selecting the leanest secure isolation envelope. Shields host credentials and filesystems completely from AI agents and untrusted dependencies with zero SSD disk wear. Provides mathematical proof of execution integrity for enterprise and mission-critical workloads.
- **Tolerable Trade-off:** Managing dynamic domain lifecycle requires maintaining the deterministic verifier and micro-Rust broker. However, all tiers build upon verified existing primitives (`bwrap`, `cgroups v2`, `QEMU`, `state.py`), guaranteeing zero host destabilization and full backward compatibility.
