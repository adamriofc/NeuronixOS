# ADR-004: Upstream Synchronization and Fork Mitigation Strategy

## Status
**Accepted** (Approved for NEURONIX OS Standalone Distribution)

## Context & Problem Statement
Many derivative Linux distributions fork their upstream distribution's package repositories. Over time, maintaining a full downstream fork of a massive package collection leads to unsustainable maintenance overhead, delayed security patches, and eventual project abandonment.

## Architectural Decision
NEURONIX **strictly avoids forking nixpkgs** (never forks upstream repositories):
- NEURONIX acts as an opinionated, declarative architectural layer constructed entirely on top of official upstream NixOS channels (`nixos-24.11` / `nixos-unstable`).
- Custom components (`neuronix-center`, `neuronix-cli`, branding, and modules) are packaged as pure Nix overlays and Flake inputs.
- Hardware hardening and system tuning are implemented as modular NixOS configuration modules (`modules/`).

## Consequences
- **Positive:** Zero downstream packaging lag for security CVE patches; full compatibility with the 100,000+ packages in upstream nixpkgs; maintenance burden remains focused on distribution UX and hardware resilience.
- **Trade-off:** Changes to upstream NixOS module options must be tracked and tested across release cycles via our automated CI test harness.
