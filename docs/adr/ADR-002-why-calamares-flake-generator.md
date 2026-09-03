# ADR-002: Declarative Flake Generation within Calamares

## Status
**Accepted** (Approved for NEURONIX OS Standalone Distribution)

## Context & Problem Statement
Standard Linux graphical installers (including vanilla Calamares implementations) operate as imperative rootfs unpackers: they dump pre-built squashfs disk images onto raw target partitions.
If applied naively to NixOS, this breaks the core paradigm:
1. The target machine inherits an unmanaged, mutable state.
2. Generating a reproducible configuration post-install requires reverse-engineering the installed state.
3. The host loses cryptographic verification from first boot.

## Architectural Decision
NEURONIX re-engineers Calamares to act strictly as a **Declarative Flake Generator**:
- The graphical wizard collects user preferences (disk partitioning, locale, keyboard, user accounts, and desktop environment).
- Rather than extracting an imperative image, Calamares invokes `installer/engine/neuronix-install-engine.sh`.
- The engine synthesizes a customized, valid `flake.nix` and `hardware-configuration.nix` at `/mnt/etc/nixos/`.
- The engine executes the official `nixos-install --flake /mnt/etc/nixos#neuronix-desktop` pipeline.

## Consequences
- **Positive:** The installed system is 100% declarative from initial boot; users can immediately manage, inspect, or rebuild their system via Git; zero imperative drift between live media and the installed OS.
- **Trade-off:** Installation requires evaluating Nix derivations and copying closures from the local ISO store, requiring an installation duration of 4 to 8 minutes on standard NVMe/SSD media.
