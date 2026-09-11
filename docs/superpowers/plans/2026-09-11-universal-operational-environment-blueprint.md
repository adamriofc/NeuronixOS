# Implementation Plan: NEURONIX OS - Universal Operational Environment (UOE) Master Blueprint

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish the foundational architecture, formal schemas, execution provider interfaces, dynamic multi-factor scoring resolver, and empirical test harness for the NEURONIX Universal Operational Environment (UOE), unifying the Universal Execution Fabric (UEF) and the Operational Semantic Layer (OSL) while strictly preserving the certified v1.0.4 baseline (1,353 assertions green).

**Architecture:** NEURONIX operates as a Universal Operational Semantic Overlay on top of Linux and NixOS as its primary native substrate. The system cleanly separates execution mechanics (UEF) from operational meaning (OSL) via the Operational Contract Envelope (OCE) primitive, resolved dynamically through multi-factor scoring across on-demand execution providers (Native, Rootfs/Bwrap, OCI) with zero overhead on native workloads and fail-closed security.

**Tech Stack:** Python 3.12+ (Core Engine, Resolver, Schemas), Rust (Conductor native terminal surface), Nix / NixOS 24.11 (Declarative host substrate), JSON Schema Draft 2020-12 / RFC 8785 JCS (Deterministic canonicalization), Bubblewrap & crun (Isolated execution runtimes).

## Global Constraints

- Strictly ZERO Unicode em-dashes (code point U+2014) and en-dashes (code point U+2013); only ASCII hyphens `-` or colons `:`.
- All code, schemas, commit messages, and documentation must be 100% in English.
- Pure Rust in `packages/conductor` (zero external crates).
- Preservation of the certified rock-solid v1.0.4 baseline (1,353 assertions green).
- Fail-closed security: any invariant violation or unverified authority defaults to execution rejection.
- Zero speculative performance claims: all metrics must be empirically benchmarked and proven.

---

## User Review Required

> [!IMPORTANT]
> - **Universal Operational Environment (UOE) Identity:** NEURONIX does not replace the Linux kernel or rewrite package ecosystems; it introduces an operational semantic overlay giving typed meaning (`Intent`, `Actor`, `Authority`, `Environment`, `Preconditions`, `Expected Effects`, `Invariants`, `Evidence`, `Outcome`) to operational change.
> - **Selective Semanticization:** Proportional overhead design. Tier 0 operations (read-only probes, standard local commands) pass through with near-zero overhead; Tier 1 operations (service, package mutations) generate lightweight contract envelopes; Tier 2 operations (destructive storage, privilege escalation, boot changes) enforce full dry-run rehearsals, StateRoot commitments, and interactive Conductor approval.
> - **On-Demand MVP Execution Providers:** The initial UEF MVP implements three lightweight, on-demand providers:
>   1. `NativeLinuxProvider`: Direct execution on host NixOS/Linux with 0% proxy penalty.
>   2. `RootfsBwrapProvider`: Unprivileged Bubblewrap sandbox for foreign Linux rootfs environments.
>   3. `OciContainerProvider`: Container-standard runtime via crun/podman for portable containerized workflows.
> - **Resource Governance (The 8 Non-Negotiable Rules):** Zero idle daemons, no unnecessary virtual machines, ephemeral execution state reclaimed on exit, lean ISO footprint, and independent layer cache cleanup.

---

## Proposed Changes

### Component 1: Formal Data Schemas & Canonical Contracts

Deliver Draft 2020-12 JSON schemas canonicalized via RFC 8785 for the core UOE primitives.

#### [NEW] [operational_contract_envelope.schema.json](file:///home/adamrofc/.gemini/antigravity/scratch/NeuronixOS/data/schemas/operational_contract_envelope.schema.json)
- Define the canonical schema for the Operational Contract Envelope (`OCE`):
  - `intent`: Unique action identifier, category (`READ`, `PROPOSE`, `MUTATE`), description, target resource URI.
  - `actor`: Principal identifier, principal type (`HUMAN_OWNER`, `HUMAN_OPERATOR`, `AI_AGENT`, `SYSTEM_DAEMON`), session nonce.
  - `authority`: Delegation tier (`OBSERVE_ONLY`, `PROPOSE_ONLY`, `DELEGATED_SCOPED`, `FULL_OPERATOR`), cryptographic delegation token (`DEL-...`), signature, expiration.
  - `environment`: Target execution context, required capabilities, ABI, network posture, isolation tier.
  - `preconditions`: Required state root, required hardware flags, lock requirements.
  - `expected_effects`: Declared state diff, filesystem changes, network mutations, rollback recipe.
  - `invariants`: Required security invariants (`INV-SEC-001` through `INV-SEC-020`).
  - `evidence`: Proof hashes, input digests, previous execution receipts.
  - `outcome`: Execution receipt binding, exit status, actual state diff, verification signature.

#### [NEW] [compatibility_contract.schema.json](file:///home/adamrofc/.gemini/antigravity/scratch/NeuronixOS/data/schemas/compatibility_contract.schema.json)
- Define the schema for execution provider capability registration:
  - `provider_id`: Unique provider identifier (`native.linux`, `rootfs.bwrap`, `oci.crun`).
  - `provider_type`: Enum (`NATIVE_LINUX`, `ROOTFS_BWRAP`, `OCI_CONTAINER`, `WASM_SANDBOX`, `MICRO_VM`).
  - `supported_formats`: Formats supported (`nix-closure`, `elf-binary`, `rootfs-dir`, `oci-image`, `wasm-module`).
  - `isolation_level`: Score from 0.0 to 1.0 (host namespace to hypervisor VM).
  - `startup_latency_class`: Expected latency (`SUB_MILLISECOND`, `LOW_MILLISECOND`, `COLD_START_HEAVY`).
  - `resource_overhead_class`: Memory/CPU footprint (`ZERO_OVERHEAD`, `MINIMAL_NAMESPACES`, `HEAVY_ISOLATION`).
  - `hardware_requirements`: KVM flags, rootless namespace requirements, GPU access requirements.

#### [NEW] [execution_receipt.schema.json](file:///home/adamrofc/.gemini/antigravity/scratch/NeuronixOS/data/schemas/execution_receipt.schema.json)
- Define the execution receipt schema binding execution results to cryptographic evidence roots.

---

### Component 2: Execution Provider Architecture & Runtime Interfaces

Implement the core execution fabric provider interfaces and lifecycle contracts in `neuronix-core`.

#### [NEW] [provider.py](file:///home/adamrofc/.gemini/antigravity/scratch/NeuronixOS/packages/neuronix-core/neuronix_core/uef/provider.py)
- Define abstract base class `ExecutionProvider`:
  - `provider_id`: Read-only property returning unique provider identifier.
  - `discover() -> ProviderCapability`: Probe system support (e.g. check `/dev/kvm`, bubblewrap binary, binfmt_misc).
  - `inspect(workload: WorkloadSpec) -> CompatibilityReport`: Verify whether workload can execute on this provider.
  - `score(workload: WorkloadSpec, context: OperationalContext) -> float`: Multi-factor score evaluation.
  - `prepare(workload: WorkloadSpec) -> PreparedEnvironment`: Ephemeral sandbox and mount configuration.
  - `execute(prepared: PreparedEnvironment, envelope: OperationalContractEnvelope) -> ExecutionReceipt`: Synchronous or asynchronous execution.
  - `cleanup(prepared: PreparedEnvironment) -> ResourceReleaseProof`: Immediate cleanup of namespaces and tmpfs mounts.

#### [NEW] [native_provider.py](file:///home/adamrofc/.gemini/antigravity/scratch/NeuronixOS/packages/neuronix-core/neuronix_core/uef/native_provider.py)
- Implement `NativeLinuxProvider`:
  - Direct execution for native ELF binaries and Nix derivations.
  - Zero performance tax; direct POSIX execution with optional Landlock / seccomp policy enforcement.

#### [NEW] [rootfs_provider.py](file:///home/adamrofc/.gemini/antigravity/scratch/NeuronixOS/packages/neuronix-core/neuronix_core/uef/rootfs_provider.py)
- Implement `RootfsBwrapProvider`:
  - Unprivileged user namespace execution via `bwrap`.
  - Bind mounts for target rootfs, read-only system protections, isolated volatile `/tmp` and `/home`.

#### [NEW] [oci_provider.py](file:///home/adamrofc/.gemini/antigravity/scratch/NeuronixOS/packages/neuronix-core/neuronix_core/uef/oci_provider.py)
- Implement `OciContainerProvider`:
  - Standard OCI container runtime integration (`crun` or fallback container engines).
  - Rootless namespace, network policy isolation, and cgroup resource bounding.

---

### Component 3: Dynamic Multi-Factor Scoring Resolver

Implement the intelligent resolver selecting the optimal execution provider dynamically.

#### [NEW] [resolver.py](file:///home/adamrofc/.gemini/antigravity/scratch/NeuronixOS/packages/neuronix-core/neuronix_core/uef/resolver.py)
- Implement `ProviderResolver`:
  - Registry of available providers.
  - Mathematical multi-factor evaluation formula:
    `Score = C_compat * (w1 * P_policy + w2 * I_isolation + w3 * R_resource_cost + w4 * L_latency + w5 * Q_provenance)`
  - Deterministic tie-breaking and graceful fallback degradation chain.
  - Rejection with typed diagnostic report if no provider meets minimum compatibility threshold.

---

### Component 4: Operational Semantic Layer (OSL) & Coherence Engine

Implement the semantic evaluation engine wrapping workloads in operational contract envelopes.

#### [NEW] [coherence.py](file:///home/adamrofc/.gemini/antigravity/scratch/NeuronixOS/packages/neuronix-core/neuronix_core/osl/coherence.py)
- Implement `CoherenceEngine`:
  - Validates `OperationalContractEnvelope` against active `StateCommitment` (`StateRoot`).
  - Selective semanticization tiers:
    - `Tier 0 (PASSTHROUGH)`: Read operations; bypass heavy cryptographic envelope, return raw output.
    - `Tier 1 (LIGHTWEIGHT)`: Service status and configuration inquiries; record minimal execution receipt.
    - `Tier 2 (FULL_CONTRACT)`: Mutations, storage plans, privilege escalations; require preflight dry-run, invariant check, and approval token.
  - Verify security invariants (`INV-SEC-001` through `INV-SEC-020`) before authorizing state mutation.

#### [MODIFY] [skills.py](file:///home/adamrofc/.gemini/antigravity/scratch/NeuronixOS/packages/neuronix-core/neuronix_core/skills.py)
- Bridge existing `SkillDispatcher` to `CoherenceEngine`:
  - Allow skills to emit `OperationalContractEnvelope` instances.
  - Route execution through the resolved UEF provider when cross-environment capabilities are specified.

---

### Component 5: Conductor Interactive Surface Integration

Enable the Conductor terminal user interface to display OCE proposals and provider scoring details.

#### [MODIFY] [packages/conductor/src/surface.rs](file:///home/adamrofc/.gemini/antigravity/scratch/NeuronixOS/packages/conductor/src/surface.rs)
- Render proposal details in the slide-over overlay:
  - Display resolved provider (`Native`, `Rootfs/bwrap`, `OCI`).
  - Display calculated multi-factor provider score and blast radius.
  - Display target invariants and required human approval keybindings (`[Y] Approve`, `[N] Reject`, `[D] Diff`).

---

### Component 6: Documentation & Specification Synchronization

Document the complete UOE architecture in the repository specifications and update the README.

#### [NEW] [docs/architecture/universal-operational-environment.md](file:///home/adamrofc/.gemini/antigravity/scratch/NeuronixOS/docs/architecture/universal-operational-environment.md)
- Complete technical specification covering UOE, UEF, OSL, OCE, Dynamic Scoring, and Lean Resource Economics.

#### [MODIFY] [README.md](file:///home/adamrofc/.gemini/antigravity/scratch/NeuronixOS/README.md)
- Update architectural overview to introduce the Universal Operational Environment roadmap.
- Clarify that Linux/NixOS is the first-class host substrate and all v1.0.4 production guarantees remain certified.

---

## Detailed Task Breakdown

### Task 1: Create Core Data Schemas for UOE

**Files:**
- Create: `data/schemas/operational_contract_envelope.schema.json`
- Create: `data/schemas/compatibility_contract.schema.json`
- Create: `data/schemas/execution_receipt.schema.json`
- Test: `tests/test_uoe_schemas.py`

**Interfaces:**
- Consumes: JSON Schema Draft 2020-12 specifications.
- Produces: Formal validation schemas for envelopes, capability declarations, and receipts.

- [x] **Step 1: Write the failing test for UOE schemas**
Create `tests/test_uoe_schemas.py` validating schema syntax, required fields, and sample valid/invalid payloads.

- [x] **Step 2: Run test to verify it fails**
Run: `python3 -m unittest tests/test_uoe_schemas.py -v`
Expected: FAIL with missing schema files or import errors.

- [x] **Step 3: Implement the three JSON schemas**
Write `operational_contract_envelope.schema.json`, `compatibility_contract.schema.json`, and `execution_receipt.schema.json`.

- [x] **Step 4: Run test to verify it passes**
Run: `python3 -m unittest tests/test_uoe_schemas.py -v`
Expected: PASS with 100% assertions green.

- [x] **Step 5: Verify zero Unicode dashes**
Run: `python3 -c "for f in ['data/schemas/operational_contract_envelope.schema.json', 'data/schemas/compatibility_contract.schema.json', 'data/schemas/execution_receipt.schema.json', 'tests/test_uoe_schemas.py']: text=open(f).read(); assert '\u2014' not in text and '\u2013' not in text, f"`

- [x] **Step 6: Commit**
```bash
git add data/schemas/ tests/test_uoe_schemas.py
git commit -m "feat(schema): add canonical schemas for UOE operational contract envelopes and execution receipts"
```

---

### Task 2: Implement ExecutionProvider Abstract Interface & Data Models

**Files:**
- Create: `packages/neuronix-core/neuronix_core/uef/__init__.py`
- Create: `packages/neuronix-core/neuronix_core/uef/models.py`
- Create: `packages/neuronix-core/neuronix_core/uef/provider.py`
- Test: `tests/test_uef_provider_interface.py`

**Interfaces:**
- Consumes: Python dataclasses, typing protocols, RFC 8785 canonicalization.
- Produces: `ExecutionProvider`, `WorkloadSpec`, `ProviderCapability`, `PreparedEnvironment`, `ExecutionReceipt`.

- [x] **Step 1: Write the failing test for ExecutionProvider interfaces**
Write tests asserting that subclasses implement all lifecycle methods (`discover`, `inspect`, `score`, `prepare`, `execute`, `cleanup`) and handle failures cleanly.

- [x] **Step 2: Run test to verify it fails**
Run: `python3 -m unittest tests/test_uef_provider_interface.py -v`
Expected: FAIL with module not found.

- [x] **Step 3: Implement data models and abstract provider class**
Write `models.py` and `provider.py` with full type annotations, docstrings, and invariant checks.

- [x] **Step 4: Run test to verify it passes**
Run: `python3 -m unittest tests/test_uef_provider_interface.py -v`
Expected: PASS.

- [x] **Step 5: Commit**
```bash
git add packages/neuronix-core/neuronix_core/uef/ tests/test_uef_provider_interface.py
git commit -m "feat(uef): implement abstract ExecutionProvider lifecycle and data models"
```

---

### Task 3: Implement NativeLinuxProvider (0% Overhead Host Execution)

**Files:**
- Create: `packages/neuronix-core/neuronix_core/uef/native_provider.py`
- Test: `tests/test_uef_native_provider.py`

**Interfaces:**
- Consumes: `ExecutionProvider`, `subprocess`, `os`, `shutil`.
- Produces: `NativeLinuxProvider` with host execution and resource tracking.

- [x] **Step 1: Write the failing test for NativeLinuxProvider**
Test execution of system binaries, argument passing, environment variable propagation, exit code handling, and zero-tax execution.

- [x] **Step 2: Run test to verify it fails**
Run: `python3 -m unittest tests/test_uef_native_provider.py -v`
Expected: FAIL with module not found.

- [x] **Step 3: Implement NativeLinuxProvider**
Write `native_provider.py` ensuring non-blocking execution options, timeout enforcement, and memory cleanup.

- [x] **Step 4: Run test to verify it passes**
Run: `python3 -m unittest tests/test_uef_native_provider.py -v`
Expected: PASS.

- [x] **Step 5: Commit**
```bash
git add packages/neuronix-core/neuronix_core/uef/native_provider.py tests/test_uef_native_provider.py
git commit -m "feat(uef): implement NativeLinuxProvider with zero-overhead execution"
```

---

### Task 4: Implement RootfsBwrapProvider (Unprivileged Bubblewrap Isolation)

**Files:**
- Create: `packages/neuronix-core/neuronix_core/uef/rootfs_provider.py`
- Test: `tests/test_uef_rootfs_provider.py`

**Interfaces:**
- Consumes: `ExecutionProvider`, Bubblewrap binary discovery, user namespaces.
- Produces: `RootfsBwrapProvider` executing binaries inside isolated rootfs trees.

- [x] **Step 1: Write the failing test for RootfsBwrapProvider**
Test capability discovery (bwrap check), mount table preparation, mock bwrap invocation, sandbox boundary enforcement, and cleanup.

- [x] **Step 2: Run test to verify it fails**
Run: `python3 -m unittest tests/test_uef_rootfs_provider.py -v`
Expected: FAIL with module not found.

- [x] **Step 3: Implement RootfsBwrapProvider**
Write `rootfs_provider.py` with sandboxed filesystem isolation, tmpfs mounts, read-only system binding, and signal handling.

- [x] **Step 4: Run test to verify it passes**
Run: `python3 -m unittest tests/test_uef_rootfs_provider.py -v`
Expected: PASS.

- [x] **Step 5: Commit**
```bash
git add packages/neuronix-core/neuronix_core/uef/rootfs_provider.py tests/test_uef_rootfs_provider.py
git commit -m "feat(uef): implement RootfsBwrapProvider for unprivileged foreign rootfs isolation"
```

---

### Task 5: Implement OciContainerProvider (Micro-Container Standard Runtime)

**Files:**
- Create: `packages/neuronix-core/neuronix_core/uef/oci_provider.py`
- Test: `tests/test_uef_oci_provider.py`

**Interfaces:**
- Consumes: `ExecutionProvider`, OCI runtime (`crun`/`runc`/`podman`) detection.
- Produces: `OciContainerProvider` for running containerized application workloads.

- [x] **Step 1: Write the failing test for OciContainerProvider**
Test container image specification parsing, command generation, runtime inspection, and lifecycle isolation.

- [x] **Step 2: Run test to verify it fails**
Run: `python3 -m unittest tests/test_uef_oci_provider.py -v`
Expected: FAIL with module not found.

- [x] **Step 3: Implement OciContainerProvider**
Write `oci_provider.py` ensuring fallback detection, network namespace restriction, and proper container teardown.

- [x] **Step 4: Run test to verify it passes**
Run: `python3 -m unittest tests/test_uef_oci_provider.py -v`
Expected: PASS.

- [x] **Step 5: Commit**
```bash
git add packages/neuronix-core/neuronix_core/uef/oci_provider.py tests/test_uef_oci_provider.py
git commit -m "feat(uef): implement OciContainerProvider for portable container execution"
```

---

### Task 6: Implement Dynamic Multi-Factor Scoring Resolver

**Files:**
- Create: `packages/neuronix-core/neuronix_core/uef/resolver.py`
- Test: `tests/test_uef_resolver.py`

**Interfaces:**
- Consumes: All registered providers, `WorkloadSpec`, `OperationalContext`.
- Produces: `ProviderResolver.resolve(workload, context) -> ExecutionProvider`.

- [x] **Step 1: Write the failing test for dynamic scoring resolver**
Test mathematical scoring calculation across different workload requirements:
- Native workload -> NativeLinuxProvider scores highest.
- Foreign rootfs workload -> RootfsBwrapProvider selected.
- OCI container workload -> OciContainerProvider selected.
- Incompatible requirements -> Graceful rejection with diagnostic explanation.

- [x] **Step 2: Run test to verify it fails**
Run: `python3 -m unittest tests/test_uef_resolver.py -v`
Expected: FAIL.

- [x] **Step 3: Implement ProviderResolver**
Write `resolver.py` implementing the normalized scoring formula with customizable weights and validation gates.

- [x] **Step 4: Run test to verify it passes**
Run: `python3 -m unittest tests/test_uef_resolver.py -v`
Expected: PASS.

- [x] **Step 5: Commit**
```bash
git add packages/neuronix-core/neuronix_core/uef/resolver.py tests/test_uef_resolver.py
git commit -m "feat(uef): implement dynamic multi-factor provider scoring resolver"
```

---

### Task 7: Implement Operational Semantic Layer (OSL) & Coherence Engine

**Files:**
- Create: `packages/neuronix-core/neuronix_core/osl/__init__.py`
- Create: `packages/neuronix-core/neuronix_core/osl/coherence.py`
- Modify: `packages/neuronix-core/neuronix_core/skills.py`
- Test: `tests/test_osl_coherence.py`

**Interfaces:**
- Consumes: `StateCommitment`, `OperationalContractEnvelope`, `ProviderResolver`.
- Produces: `CoherenceEngine.evaluate(envelope) -> CoherenceVerdict`.

- [x] **Step 1: Write the failing test for CoherenceEngine**
Test 3 tiers of selective semanticization:
- Tier 0: Passthrough verification (latency < 1ms, zero state mutation).
- Tier 1: Lightweight receipt emission.
- Tier 2: Full preflight, invariant verification, rejection of missing authority.

- [x] **Step 2: Run test to verify it fails**
Run: `python3 -m unittest tests/test_osl_coherence.py -v`
Expected: FAIL.

- [x] **Step 3: Implement CoherenceEngine and skill integration**
Write `coherence.py` and connect envelope evaluation to `SkillDispatcher`.

- [x] **Step 4: Run test to verify it passes**
Run: `python3 -m unittest tests/test_osl_coherence.py -v`
Expected: PASS.

- [x] **Step 5: Commit**
```bash
git add packages/neuronix-core/neuronix_core/osl/ packages/neuronix-core/neuronix_core/skills.py tests/test_osl_coherence.py
git commit -m "feat(osl): implement CoherenceEngine with selective semanticization and invariant validation"
```

---

### Task 8: Architecture Documentation, Empirical Benchmarks & Full Verification

**Files:**
- Create: `docs/architecture/universal-operational-environment.md`
- Create: `tests/benchmarks/benchmark_uef_latency.py`
- Modify: `README.md`
- Test: Full QA master test runner (`tests/run_all_tests.sh`)

**Interfaces:**
- Consumes: All completed UOE components.
- Produces: Master architecture documentation, latency benchmark proofs, and clean assertion validation.

- [x] **Step 1: Write comprehensive architecture document**
Create `docs/architecture/universal-operational-environment.md` explaining UOE, UEF, OSL, dynamic scoring, lean resource economics, and security guarantees.

- [x] **Step 2: Implement latency benchmarking script**
Write `tests/benchmarks/benchmark_uef_latency.py` measuring resolver scoring latency, native execution overhead, and envelope validation time.

- [x] **Step 3: Update README.md**
Update `README.md` to introduce the Universal Operational Environment architecture while preserving all v1.0.4 certified qualifications.

- [x] **Step 4: Execute entire test suite and verify zero regressions**
Run: `./tests/run_all_tests.sh`
Run: `pytest tests/test_uoe_*.py tests/test_uef_*.py tests/test_osl_*.py`
Expected: 100% green across all existing and new tests.

- [x] **Step 5: Strictly verify zero Unicode dashes in repository**
Run: `python3 -c "import os; bad=['\u2014', '\u2013']; [([print(f, line) for line in open(os.path.join(r, f), errors='ignore') if any(b in line for b in bad)]) for r, d, files in os.walk('.') if not '.git' in r for f in files if f.endswith(('.md', '.py', '.json', '.sh', '.rs', '.nix'))]"`

- [x] **Step 6: Commit**
```bash
git add docs/architecture/ tests/benchmarks/ README.md
git commit -m "docs(architecture): specify Universal Operational Environment (UOE) and add empirical benchmarks"
```

---

## Verification Plan

### Automated Tests
1. **Schema Validation:**
   ```bash
   python3 -m unittest tests/test_uoe_schemas.py -v
   ```
2. **UEF Provider Lifecycle & Scoring:**
   ```bash
   python3 -m unittest tests/test_uef_provider_interface.py -v
   python3 -m unittest tests/test_uef_native_provider.py -v
   python3 -m unittest tests/test_uef_rootfs_provider.py -v
   python3 -m unittest tests/test_uef_oci_provider.py -v
   python3 -m unittest tests/test_uef_resolver.py -v
   ```
3. **OSL Coherence Engine & Selective Semanticization:**
   ```bash
   python3 -m unittest tests/test_osl_coherence.py -v
   ```
4. **Existing Regression & Master Harness Validation:**
   ```bash
   ./tests/run_all_tests.sh
   tests/test_security_invariants.sh
   ```
5. **Unicode Character Scan:**
   ```bash
   python3 -c "import os; bad=['\u2014', '\u2013']; violations = [os.path.join(r, f) for r, d, files in os.walk('.') if '.git' not in r for f in files if f.endswith(('.md', '.py', '.json', '.sh', '.rs', '.nix')) and any(b in open(os.path.join(r, f), errors='ignore').read() for b in bad)]; assert not violations, f'Unicode dash violations found in: {violations}'"
   ```

### Manual Verification
- Verify that NativeLinuxProvider executes `/bin/echo` with sub-millisecond overhead.
- Verify that RootfsBwrapProvider correctly falls back or reports unprivileged namespace readiness.
- Verify that Conductor terminal displays proposal envelopes with clear ASCII formatting.
