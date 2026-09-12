# ADR-010: Provable State Engine and Causal Lineage Architecture

## Status
**Accepted** (Codified in NIP-0002 for NEURONIX OS Standalone Distribution)

## Context & Problem Statement
Modern operating systems present state as a collection of unverified runtime observations. In the event of system instability, operators and automated agents must perform manual forensic archaeology across unstructured system logs to identify what changed, who initiated the change, and whether the system can safely recover. While declarative substrates (such as NixOS) solve static software configuration, dynamic runtime state, hardware measurements, and transition causality have remained disconnected.

## Architectural Decision
NEURONIX establishes the **Provable State Engine** as the primary architectural abstraction governing the entire operating system:
1. **Merkle StateRoot Formulation:** Every important machine state is committed into a 32-byte SHA-256 Merkle root aggregating five canonical leaves: Hardware Posture ($L_{\text{posture}}$), Software Substrate ($L_{\text{substrate}}$), Actor Provenance ($L_{\text{provenance}}$), Security Policy ($L_{\text{policy}}$), and Verification Evidence ($L_{\text{evidence}}$).
2. **Causal Lineage Ledger:** All system mutations record their parent state root, transaction ID, and caller UID (authenticated at the Linux socket layer via `SO_PEERCRED`) in an append-only cryptographic hash chain.
3. **Deterministic Attestation:** System health is proven in real time by recomputing the StateRoot against active TPM2 PCR 7/11 measurements, Nix store derivations, and the 1,384-assertion assurance taxonomy.
4. **Unified Command Interface:** The abstraction is exposed through the `neuronix state` command suite (`show`, `verify`, `explain`, `diff`, `history`, `recover`, `prove`) with sub-millisecond query performance backed by the micro-Rust systems daemon (`neuronix-daemon`).

## Consequences
- **Positive:** Unifies all independent NEURONIX subsystems (Nix, Btrfs, Rust, eBPF, UKI, TPM2, AI Copilot) into a single, cohesive paradigm. Eliminates manual forensic guesswork by mathematically identifying the exact transition that caused an invariant violation.
- **Tolerable Trade-off:** Calculating the complete 5-leaf Merkle tree incurs a negligible compute overhead of < 10 ms during state inspection.
