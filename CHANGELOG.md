# Changelog

All notable changes to NEURONIX OS will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.5] - 2026-09-12

### Added
- Exhaustive RFC 8032 Ed25519 digital signature test vectors and negative resistance test suite (`tests/test_crypto_vectors.py`).
- Security isolation profile for untrusted OCI container workloads with capability dropping, `noNewPrivileges`, user/network namespaces, read-only rootfs, and seccomp default error action.
- OCI container image reference cryptographic provenance classification (`PROVENANCE_STRONG` for digest pinning vs `PROVENANCE_NORMAL` for mutable tags).
- Modular CLI architecture: decomposed monolithic `src/neuronix` into `src/lib/` and `src/commands/` while maintaining 100% backwards compatibility and permission security invariants.
- PEP 561 typed package marker (`py.typed`) and `pyproject.toml` with mypy and ruff configurations for `neuronix-core`.
- Repository community standards: `CONTRIBUTING.md` (synchronized to 1,384 assertions), `.github/PULL_REQUEST_TEMPLATE.md`, `CODE_OF_CONDUCT.md` (Contributor Covenant 2.1), and `.editorconfig`.
- Automated release infrastructure: `.github/RELEASE_TEMPLATE.md`, `.github/dependabot.yml`, `.github/workflows/benchmark.yml`.
- Comprehensive Hardware Compatibility Matrix in `README.md`.
- End-to-end hardware contracts test suite (`tests/e2e/test_hardware_contracts.sh`).
- Property-based testing for core substrate invariants (`tests/property/test_core_invariants.py`).
- Mutation testing evaluation runner (`tests/mutation/run_mutation_evaluation.sh`).

### Changed
- Resolved OCI runtime discovery false-positive in `OciContainerProvider.discover()`: returns empty supported formats and 0.0 isolation score when no container engine is present on host.
- Reconciled release lineage: bound all verification passports, Merkle StateRoots, evidence graphs, and proof bundles to exact HEAD commit SHA for v1.0.5.
- Truthful proof classification: aligned verified release proof classes to strictly auditable L0 through L4 evidence, with L5 designated as hardware qualification target.
- Enhanced Rust documentation comments (`///`) across `neuronix-daemon` and `conductor` crates.

### Fixed
- Fixed assertion count discrepancy in `CONTRIBUTING.md`.
- Removed redundant self-referencing `Distro -> .` symlink.
- Dynamic version resolution across `tools/compile_evidence.py`, `tools/generate_verification_passport.py`, and `tools/generate_release_proof.py`.
- Fixed REG-005 historical regression assertion to correctly verify modularized concurrency locking in `src/lib/lock.sh` and active flock mutual exclusion.
- Hardened OCI seccomp profile in `packages/neuronix-core`: replaced empty syscalls with established, architecture-aware standard container userspace allowlist (x86_64, x86, aarch64) under fail-closed default-deny (`SCMP_ACT_ERRNO`).
- Enforced regression invariants prohibiting empty allowlists under default error actions, and validated end-to-end workload operational lifecycle.

## [1.0.4] - 2026-09-11

### Added
- Provable Adaptive Execution Architecture (Project Hyperion) with multi-tier execution isolation.
- Universal Execution Fabric (UEF) with native Linux, OCI container, and bubblewrap rootfs providers.
- Strictly orthogonal OCI runtime contracts (Mode A: high-level image via podman/docker; Mode B: low-level bundle via crun/runc).
- Operational Semantic Layer (OSL) with CoherenceEngine and tiered semanticization.
- NEURONIX Skill System and Delegated Authority Engine.
- Vital Laboratory Observation Subsystem and Machine Contracts.
- Authoritative Evidence Graph and Lineage Traversal.
- Verification Passport and Zero-Dependency Offline Verifier (`tools/verify_passport.py`).
- Conductor Operating Surface with VT100 terminal emulation.
- Proof-carrying release architecture with SBOM SPDX.

### Changed
- NixOS base pinned to 26.05 stable channel.
- Enhanced Rust daemon with JSON-RPC 2.0 AST engine.
- Btrfs subvolume topology with Zstandard level 3 compression and automated SSD TRIM.

### Fixed
- Fixed RTC clock synchronization for Windows dual-boot environments.
- Addressed Btrfs metadata balance timer edge cases.

## [1.0.3] - 2026-08-15

### Added
- Industrial CI & Resilience Pipeline with 14 automated verification gates.
- Ephemeral Persona and Workspace Branching via Btrfs/Reflink time-travel snapshots.
- eBPF LSM syscall container and security monitoring.
- Dual-Plane Control Engine and Resilient Measured Boot telemetry.

## [1.0.2] - 2026-07-20

### Added
- EndeavourOS feature parity: Calamares graphical installer integration, Welcome Hub, Doctor diagnostics.
- Quickstart 1-click application catalog (Flatpak/Flathub).
- Declarative Linux kernel manager (default, zen, lts, latest, hardened).

## [1.0.1] - 2026-06-15

### Added
- Autonomous background update service and staged upgrade notification system.
- 5-phase storage diet and SSD TRIM reclamation pipeline (`neuronix diet`).
- ZRAM Zstandard compression with PSI memory pressure watchdog.

## [1.0.0] - 2026-05-30

### Added
- Initial release of NEURONIX OS: Declarative, self-healing developer substrate built on NixOS.
- Hermetic developer stacks (`neuronix dev`).
- Micro-VM OS sandbox (`neuronix sandbox`).
- Ephemeral zero-copy container runtime in RAM (`neuronix container`).
