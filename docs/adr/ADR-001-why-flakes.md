# ADR-001: Pure Nix Flakes as the Primary Interface

## Status
**Accepted** (Approved for NEURONIX OS Standalone Distribution)

## Context & Problem Statement
In traditional (legacy channel-based) NixOS deployments, system state relies on imperative global channels and the ambient `$NIX_PATH` environment variable. This introduces operational challenges:
1. **Non-Deterministic Builds:** Executing `nixos-rebuild switch` across distinct machines referencing the same channel track can yield conflicting package closures if evaluated at different timestamps.
2. **Hidden State Mutations:** System channels are mutated imperatively (`nix-channel --update`), breaking auditability.
3. **Impaired Version Control:** Absence of a standardized dependency lockfile binding inputs to cryptographic commit hashes.

## Architectural Decision
NEURONIX establishes **pure Nix Flakes (`flake.nix` & `flake.lock`)** as the mandatory standard across all system configurations, packaging specifications, and developer CLI workflows:
- All Calamares installations produce a standalone `flake.nix` in `/etc/nixos/`.
- Dependency pinning is cryptographically locked within `flake.lock`.
- Enables modular, reproducible workflows such as `neuronix dev <stack>` and ephemeral micro-VM execution (`neuronix try`).

## Consequences
- **Positive:** Guaranteed bit-for-bit reproducibility across physical and virtual targets; atomic rollback points are deterministic; vulnerability audits of dependency closures are fully transparent.
- **Trade-off:** Requires enabling `nix.settings.experimental-features = [ "nix-command" "flakes" ]`, which is enabled by default in all NEURONIX images.
