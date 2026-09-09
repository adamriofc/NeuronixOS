# Specification: Security Invariant Registry & Fail-Closed Semantics

## 1. Specification Metadata
- **Specification ID:** SPEC-NRX-SEC-015
- **Title:** Security Invariant Registry and Verification Matrix
- **Version:** 2.0.0
- **Status:** AUTHORITATIVE_STANDARD
- **Scope:** Complete NEURONIX OS kernel boundary, Hyperion Execution Broker, State Engine, Storage Planner, Secret Fabric, and Verification Gates.
- **Reference Standards:** RFC 8785 (JCS), FIPS 180-4, NIST SP 800-207 (Zero Trust Architecture).

---

## 2. Executive Purpose

The Security Invariant Registry establishes a deterministic mapping between architectural security requirements, implementation modules, failure injection gates, and automated regression corpora. Every invariant MUST be fail-closed: if an integrity assertion fails or evidence is absent, the system MUST NOT proceed under an assumption of trust.

---

## 3. Invariant Registry Matrix (SEC-001 to SEC-020)

| Invariant ID | Security Invariant Title | Target Component | Failure Semantics | Automated Gate |
| :--- | :--- | :--- | :--- | :--- |
| **SEC-001** | Missing Tier 2 Isolation Boundary | `packages/neuronix-core/hyperion.py` | Fail closed if Bubblewrap or eBPF LSM unavailable | `tests/test_security_invariants.sh` |
| **SEC-002** | Missing Tier 3 Virtual Boundary | `packages/neuronix-core/hyperion.py` | Fail closed if KVM acceleration unavailable | `tests/test_security_invariants.sh` |
| **SEC-003** | Malformed HDS Contract Specification | `packages/neuronix-core/hyperion.py` | Reject before execution with structural error | `tests/test_conformance_corpus.sh` |
| **SEC-004** | Domain Proof Root Mismatch | `packages/neuronix-daemon/src/hyperion.rs` | Immediate verification rejection | `tests/test_conformance_corpus.sh` |
| **SEC-005** | Missing Runtime Execution Receipt | Python & Rust Hyperion Engines | Fail closed with `NO_RUNTIME_RECEIPT` | `tests/test_conformance_corpus.sh` |
| **SEC-006** | Receipt Replay & Nonce Omission | `packages/neuronix-core/hyperion.py` | Reject proof if nonce is missing or replayed | `tests/test_negative_reproducibility.sh`|
| **SEC-007** | StateRoot Leaf Tamper Sensitivity | `packages/neuronix-core/state.py` | Any leaf modification strictly alters StateRoot | `tests/test_negative_reproducibility.sh`|
| **SEC-008** | Age-Bounded Evidence Staleness | `packages/neuronix-core/state.py` | Degrade trust to `EXPIRED` if evidence > 7 days | `tests/test_security_invariants.sh` |
| **SEC-009** | Missing Security Policy Handling | `packages/neuronix-daemon/src/state.rs` | Degrade trust posture to `DEGRADED` | `tests/test_security_invariants.sh` |
| **SEC-010** | Zero Silent Downgrade Enforcement | Python & Rust Hyperion Engines | Reject with `ISOLATION_EVIDENCE_MISMATCH` | `tests/test_conformance_corpus.sh` |
| **SEC-011** | Capability-Bound Resource Consumption | `packages/neuronix-core/facter.py` | Fail closed on capability oversubscription | `tests/test_security_invariants.sh` |
| **SEC-012** | 7-Factor Destructive Storage Auth | `packages/neuronix-core/storage_planner.py` | Fail closed on missing factor or active mount | `tests/test_security_invariants.sh` |
| **SEC-013** | Plaintext Secret Omission from State | `packages/neuronix-core/secrets.py` | Fail closed if plaintext found in State/Logs | `tests/test_security_invariants.sh` |
| **SEC-014** | AI Secret Visibility Masking | `packages/neuronix-core/secrets.py` | Mask payloads to `METADATA_ONLY` | `tests/test_security_invariants.sh` |
| **SEC-015** | Multi-Stage Boot Health Contract | `packages/neuronix-core/boot_trust.py` | Trigger rollback if 5-stage health fails | `tests/test_security_invariants.sh` |
| **SEC-016** | Actual KVM Hypervisor Boundary Proof | `packages/neuronix-core/hyperion.py` | Fail closed if Tier 3 receipt lacks KVM binding | `tests/test_security_invariants.sh` |
| **SEC-017** | Hardware Fact Read-Only Probe Safety | `packages/neuronix-core/facter.py` | Fail closed if hardware probe alters state | `tests/test_security_invariants.sh` |
| **SEC-018** | Universal Topology Graph Causality | `packages/neuronix-core/topology.py` | Reject transitions with circular dependencies | `tests/test_security_invariants.sh` |
| **SEC-019** | AI Proposed Transition Simulation | `packages/neuronix-core/semantic.py` | Reject proposals without AST dry-run simulation | `tests/test_security_invariants.sh` |
| **SEC-020** | Decoupled State & Evidence Authenticity | `tools/verify_passport.py` | Reject passports with tautological circular proofs | `tests/test_security_invariants.sh` |

---

## 4. Invariant Verification Lifecycle

```mermaid
flowchart TD
    Req["Workload Request Arrives"] --> SEC_003{"SEC-003: Is HDS Contract Valid?"}
    SEC_003 -- Invalid --> Rej_HDS["Reject Specification (Fail Closed)"]
    SEC_003 -- Valid --> CheckTier{"Evaluate Requested Isolation Tier"}

    CheckTier -- Tier 2 --> SEC_001{"SEC-001: Is Enclave Boundary Present?"}
    SEC_001 -- No --> Rej_T2["FAIL_CLOSED (No Silent Downgrade)"]
    SEC_001 -- Yes --> Exec_T2["Execute in eBPF Enclave"]

    CheckTier -- Tier 3 --> SEC_002{"SEC-002: Is Hardware KVM Available?"}
    SEC_002 -- No --> Rej_T3["FAIL_CLOSED (No Silent Downgrade)"]
    SEC_002 -- Yes --> SEC_016{"SEC-016: Hardware KVM Bound to Receipt?"}
    SEC_016 -- No --> Rej_KVM["FAIL_CLOSED (Fake Hypervisor Rejected)"]
    SEC_016 -- Yes --> Exec_T3["Execute in Micro-VM"]

    Exec_T2 --> GenReceipt["Executor Emits Runtime Receipt"]
    Exec_T3 --> GenReceipt

    GenReceipt --> SEC_005{"SEC-005: Is Receipt Present?"}
    SEC_005 -- No --> Rej_NoRec["Verdict: NO_RUNTIME_RECEIPT (Fail Closed)"]
    SEC_005 -- Yes --> SEC_006{"SEC-006: Is Nonce Valid & Fresh?"}
    SEC_006 -- No --> Rej_Replay["Reject Replay / Nonce Missing"]
    SEC_006 -- Yes --> SEC_010{"SEC-010: Does Actual Tier == Requested Tier?"}
    SEC_010 -- Mismatch --> Rej_Downgrade["Verdict: ISOLATION_EVIDENCE_MISMATCH"]
    SEC_010 -- Match --> SEC_004{"SEC-004: Does Proof Root Match Recomputed?"}
    SEC_004 -- Mismatch --> Rej_Proof["Verdict: INVALID_PROOF_ROOT"]
    SEC_004 -- Match --> Certified["Verdict: VERIFIED_TRUSTED"]
```
