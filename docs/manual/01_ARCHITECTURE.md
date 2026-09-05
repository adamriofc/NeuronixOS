# Chapter 1: Platform Architecture & Substrate Invariants

## 1. Architectural Philosophy

NEURONIX OS is an industrial declarative Linux distribution engineered on top of a pure-functional NixOS substrate. Unlike conventional Linux distributions (Ubuntu, Arch, Fedora) where the filesystem is mutable and software installation alters shared dynamic libraries in-place, NEURONIX decouples system state into pure functional derivations:

1. **Immutable System Store:** All packages and system closures reside under `/nix/store/<hash>-<name>`, which is mounted read-only during normal operations.
2. **Atomic Symlink Activations:** System states are represented as symbolic link generations managed by `nix-env` and `systemd-boot`. Switching generations is an atomic pointer swap.
3. **Decoupled User Space:** User data (`/home`) resides on a dedicated Btrfs subvolume (`@home`), guaranteeing that rolling back or rebuilding the operating system never mutates or overwrites user documents.

---

## 2. Four-Layer Platform Architecture

```text
                                  NEURONIX OS PLATFORM
                                           │
  ┌────────────────────────────────────────┴────────────────────────────────────────┐
  │                                                                                 │
[ LAYER 1: USER EXPERIENCE (UX) ]                               [ LAYER 2: DESKTOP & SYSTEM CORE ]
  ├─ Calamares Declarative Installer Engine                       ├─ Pure Nix Substrate (Immutable /nix/store)
  ├─ NEURONIX Center (GUI System Hub & Telemetry)                 ├─ 27 Hardware Configuration Pillars
  ├─ Generation Management & Instant Symlink Rollbacks            ├─ Global Dynamic Linker (nix-ld for FHS binaries)
  ├─ Dual-Layer Software Model (Nix Core + Flathub Flatpak)       ├─ Atomic Symlink Pointer Management
  └─ Desktop Environments: KDE Plasma 6, GNOME 47, Hyprland       └─ Generation-Aware Shell Prompt [Gen #N]
  │                                                                                 │
  ├─────────────────────────────────────────────────────────────────────────────────┤
  │                                                                                 │
[ LAYER 3: DEVELOPER ENGINE ]                                   [ LAYER 4: RELIABILITY & AI SUBSTRATE ]
  ├─ neuronix dev python (uv, ruff, pyright, postgresql)          ├─ Model Context Protocol (MCP) Server (JSON-RPC 2.0)
  ├─ neuronix dev rust   (rustc, cargo, rust-analyzer, clippy)   ├─ In-Memory Shadow Micro-VM Simulator (neuronix try)
  ├─ neuronix dev node   (node 20, pnpm, typescript, eslint)      ├─ Declarative Derivation Verification (neuronix verify)
  ├─ neuronix dev ai     (pytorch, cuda, ollama, jupyterlab)      ├─ Storage Pruner & VirtIO TRIM (neuronix diet)
  └─ neuronix dev go     (compiler, gopls, golangci-lint, delve)  └─ 1,038 Automated Test Assertions (100% Pass)
```

---

## 3. Formal Proof Class Taxonomy (P0 through P4)

To ensure empirical truthfulness and eliminate ambiguous claims, all capabilities in NEURONIX OS are governed by five formal proof classes:

| Proof Class | Rigor Level & Scope | Verification Grounding | Subsystems & Features |
| :--- | :--- | :--- | :--- |
| **P0: Mathematical Determinism** | Functional derivations, bit-identical store paths, pinned inputs. | Verified via Nix derivation graph, `flake.lock` pinned commit, and RFC SHA-256 digests. | Pure Nix substrate, pinned Nixpkgs closures, reproducible ISO builds, release manifest hashes. |
| **P1: Automated CI Verification** | System regression suites, multi-architecture evaluations, micro-VM boots. | Validated through 1,038 automated test assertions across 25 QA master suites, 19 distro component suites, and 14 lifecycle gates. | Multi-arch evaluation, Shadow VM lifecycle, Calamares flake generation, CLI argument fuzzing, MCP JSON-RPC. |
| **P2: Qualified Reference Hardware** | Empirical hardware validation on representative bare-metal systems. | Validated across 8 reference platforms (ThinkPad, Framework, AMD/Intel workstations, XPS, Zephyrus, Apple Silicon). | Intel/AMD microcode, Mesa RADV, Intel Arc Xe, NVIDIA PRIME offload, S3/s2idle power management, PipeWire HD audio. |
| **P3: Declarative Module Support** | Composable NixOS configuration modules and subsystem policies. | 27 hardware configuration pillars managed in `modules/hardware/` and `data/hardware_qualification.json`. | ZRAM ZSTD swap, systemd-oomd memory monitor, Btrfs subvolumes (@, @home, @nix, @log, @snapshots), auto-TRIM. |
| **P4: Experimental / Community** | Optional hardware features, custom Wayland compositor rules, community packages. | Documented with operational caveats and manual verification steps in operational runbooks. | Lanzaboote UEFI Secure Boot signing chain, TPM2 LUKS auto-unlocking, custom Hyprland animations. |
