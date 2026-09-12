# NIP-0002: The Provable State Architecture and Causality Ledger

- **NIP Number:** 0002
- **Title:** The Provable State Architecture and Causality Ledger
- **Author:** NEURONIX OS Core Engineering Group
- **Status:** Active / Accepted
- **Created:** 2026-09-09
- **Target Release:** v1.0.5+

---

## 1. Executive Summary

This proposal establishes the foundational architectural standard for NEURONIX as **The Provable Operating System**. It unifies existing declarative substrates (NixOS Flakes), snapshot file storage (Btrfs subvolumes), hardware measurements (TPM2 PCR 7/11), security policy envelopes (eBPF LSM contracts), micro-Rust control planes (`neuronix-daemon`), and continuous validation gates into a singular mathematical abstraction: the **Provable State Engine**.

Under this paradigm:
- Every important machine state has a 32-byte Merkle **`StateRoot`** identifier.
- Every state transition preserves a causal record of its trigger intent, authenticated caller (via kernel `SO_PEERCRED`), and parent state.
- System integrity is proven deterministically against physical hardware and declared invariants rather than assumed.
- Any failure or drift provides an automated, mathematically verified path to the predecessor trusted state.

---

## 2. Motivation: From Reported State to Provable State

Traditional operating systems operate under an unverified epistemological model: they report what they *believe* is true (*Reported State*), such as installed packages, running systemd units, and mounted filesystems, without providing cryptographic proof that the running machine matches that representation.

NEURONIX establishes the **Axiom of Provable State**:
> *"No Important State Without Proof. Every State Has an Identity, Every Transition Has a Reason, Every Failure Has a Recovery Path."*

Any state lacking cryptographic evidence and invariant verification is formally classified as `UNTRUSTED` or `DRIFT_DETECTED`.

---

## 3. Merkle StateRoot Specification

The state of a NEURONIX workstation is mathematically committed into a 32-byte SHA-256 Merkle root derived from five distinct leaves:

```text
                           STATE ROOT (SHA-256)
                                    │
       ┌────────────────────────────┼────────────────────────────┐
       │                            │                            │
   BRANCH 1                     BRANCH 2                     BRANCH 3
[POSTURE LEAF]               [SUBSTRATE LEAF]            [PROVENANCE LEAF]
  ├─ Boot (PCR 7+11)           ├─ Nix System Path          ├─ Prev State Root
  └─ Hardware Integrity        └─ Config Flake Hash        ├─ Actor (SO_PEERCRED)
                                                           └─ Event / Intent
                                    │
       ┌────────────────────────────┴────────────────────────────┐
       │                                                         │
   BRANCH 4                                                  BRANCH 5
[POLICY LEAF]                                             [EVIDENCE LEAF]
  ├─ eBPF LSM Policy Hash                                   ├─ Invariant Matrix Result
  └─ Lanzaboote PCR Rules                                   └─ Journal Tx Status
```

All leaf structures are normalized using RFC 8785 Canonical JSON Serialization (JCS) before hashing, ensuring 100% byte-for-byte reproducibility regardless of language runtime or architecture.

### The Five State Leaves:

1. **Leaf 1: Posture ($L_{\text{posture}}$):**  
   Encapsulates hardware measurements from TPM2 PCR 7 (Secure Boot certificate validation) and PCR 11 (Unified Kernel Image binary hash), alongside kernel release identifiers. When hardware TPM2 is absent, a deterministic null sentinel is recorded with `synthetic_emulated` policy.
2. **Leaf 2: Substrate ($L_{\text{substrate}}$):**  
   Encapsulates the immutable Nix store closure path (`/run/current-system`), active generation index, host architecture, and flake lockfile digest.
3. **Leaf 3: Provenance ($L_{\text{provenance}}$):**  
   Encapsulates the parent $\text{StateRoot}_{n-1}$, Sentinel transaction identifier, actor UID/GID authenticated via socket `SO_PEERCRED`, and trigger event name.
4. **Leaf 4: Policy ($L_{\text{policy}}$):**  
   Encapsulates the declarative security contract hash (eBPF LSM module options, protected path allowlists, and Lanzaboote PCR binding rules).
5. **Leaf 5: Evidence ($L_{\text{evidence}}$):**  
   Encapsulates the execution results of the continuous industrial assurance taxonomy (1,384 assertions across 32 master suites) and journal chain cryptographic continuity.

---

## 4. State Causality and Causal Localization

State transitions form an immutable directed acyclic graph (DAG):
$$S_n = \delta(S_{n-1}, T, A, P)$$
Where $T$ is the transaction payload, $A$ is the authenticated actor, and $P$ is the applicable policy envelope.

When an invariant violation occurs, the Provable State Engine performs **causal localization**:
1. Identifies the exact transition $S_{n-1} \to S_n$ that introduced the invariant failure.
2. Formulates a structured delta explaining the root-cause parameter or package change.
3. Restores the physical machine to certified state $S_{n-1}$ via atomic generation switching.

---

## 5. Interface Contract: `neuronix state`

The Provable State Engine is exposed to operators, automation scripts, and local AI agents through a unified CLI suite:

- `neuronix state show [--json]`: Displays active StateRoot and 5-leaf Merkle status.
- `neuronix state verify [--json]`: Executes cryptographic verification against live measurements.
- `neuronix state explain`: Emits natural-language causal analysis.
- `neuronix state diff [STATE_A] [STATE_B]`: Explains structural differences between two states.
- `neuronix state history`: Displays chronological transition lineage.
- `neuronix state recover [--to-last-trusted]`: Restores certified predecessor state.

Local AI copilots interface with this engine through native Model Context Protocol (MCP) tools (`neuronix_state_show`, `neuronix_state_verify`), acting as intelligent diagnostic interpreters while respecting the `SO_PEERCRED` mutation boundary.
