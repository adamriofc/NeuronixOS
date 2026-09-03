# NEURONIX Specification: Security Architecture & Verification Protocol

> **Document ID:** `NRX-SEC-003`  
> **Status:** APPROVED  
> **Path:** `docs/specifications/03_SECURITY_AND_VERIFICATION.md`  

---

## 1. Threat Model & Defensive Architecture

NEURONIX adopts a defense-in-depth posture across its operational layers:

### 1.1 Threat Matrix (STRIDE Analysis)

| Threat Domain | Classical Desktop Linux Risk | NEURONIX Defensive Implementation |
| :--- | :--- | :--- |
| **Spoofing** | Processes spoofing elevated root privileges. | Non-root execution constrained within unprivileged user namespaces. |
| **Tampering** | Accidental mutation or deletion of `/usr/lib` or `/bin`. | Core package hierarchy (`/nix/store`) is mounted **Read-Only** at the kernel level. |
| **Repudiation** | Untracked imperative changes obscuring the root cause of failures. | Every system transition is recorded in atomic **generations** linked to Git commits. |
| **Information Disclosure** | Plaintext credentials stored in environment variables or scripts. | Declarative secret management integration using cryptographic keys. |
| **Denial of Service** | Rogue processes consuming storage until disk exhaustion occurs. | Storage thresholds (`min-free`) trigger autonomous garbage collection before lockup. |
| **Elevation of Privilege** | Untrusted scripts escaping execution boundaries. | PolKit graphical privilege gates and wheel-restricted sudo access policies. |

---

## 2. Multi-Stage Verification Pipeline

System configuration changes and package installations are evaluated through a 5-stage verification gate before activation:

```text
  [ Proposed Configuration ]
        │
        ▼
  ┌───────────┐    Fail
  │ Stage 1   │ ───────────► [ Auto-Reject: Syntax & AST Parsing Error ]
  │ AST Check │
  └─────┬─────┘
        │ Pass
        ▼
  ┌───────────┐    Fail
  │ Stage 2   │ ───────────► [ Abort: Closure Evaluation Failure (Zero Blast Radius) ]
  │ Dry-Build │
  └─────┬─────┘
        │ Pass
        ▼
  ┌───────────┐    Fail
  │ Stage 3   │ ───────────► [ Destroy Sandbox & Output Failure Diagnostics ]
  │ Shadow VM │
  └─────┬─────┘
        │ Pass
        ▼
  ┌───────────┐
  │ Stage 4   │ ───────────► [ Atomic Switch: 1-Step Symlink Pointer Swap ]
  │ Promotion │
  └─────┬─────┘
        │
        ▼
  ┌───────────┐    Fail
  │ Stage 5   │ ───────────► [ Trigger Instant Generation Rollback (< 2 Seconds) ]
  │ Telemetry │
  └───────────┘
```

### Stage Details
1. **Stage 1: Syntax & AST Parsing:** Evaluates whether target expressions parse into valid Nix Abstract Syntax Trees (`nix-instantiate --parse`).
2. **Stage 2: Dry-Build Closure Evaluation:** Evaluates derivation trees against nixpkgs without building or activating binaries (`nixos-rebuild dry-build`).
3. **Stage 3: Shadow Micro-VM Execution (`neuronix try`):** Boots target configuration inside an ephemeral in-RAM micro-VM via QEMU with read-only 9P store sharing.
4. **Stage 4: Atomic Generation Switch:** Atomically updates the `/nix/var/nix/profiles/system` symlink.
5. **Stage 5: Post-Activation Telemetry:** Validates systemd unit health and provides instantaneous rollback (`neuronix undo`) if anomalies are detected.
