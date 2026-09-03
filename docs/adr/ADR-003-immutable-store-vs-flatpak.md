# ADR-003: Dual-Layer Architecture: Immutable Nix Core vs Sandboxed Flatpak

## Status
**Accepted** (Approved for NEURONIX OS Standalone Distribution)

## Context & Problem Statement
Desktop Linux users require rapid access to third-party proprietary and desktop software (e.g., Discord, Spotify, Steam, VS Code, Slack, Zoom).
Managing all graphical applications exclusively via Nix derivations introduces friction:
1. **Rebuild Latency:** Installing a desktop app via Nix requires modifying `/etc/nixos/configuration.nix` and running `nixos-rebuild switch`, triggering generation rebuilds for everyday desktop apps.
2. **Desktop Integration Gaps:** Complex graphical packages can occasionally have packaging quirks or missing sandboxing under strict Nix isolation.

## Architectural Decision
NEURONIX implements a **Dual-Layer Software Distribution Model**:
1. **Immutable Nix Core:** Kernel, system daemons, hardware drivers, system libraries, shell environments, development toolchains (`neuronix dev`), and core system utilities are managed strictly through declarative Nix modules.
2. **Flathub Sandboxed Applications:** Everyday graphical desktop applications are installed through Flathub via pre-configured Flatpak integrations.
3. **Portal Sandboxing:** Native Wayland session integration is enforced using `xdg-desktop-portal` backends.

## Consequences
- **Positive:** Core operating system stability and immutability remain uncompromised; non-root users can install and update desktop applications instantly via KDE Discover or GNOME Software without root permissions or system recompilation.
- **Trade-off:** Two package managers exist simultaneously; CLI documentation and Control Center UI must clearly distinguish between system derivations and user Flatpak applications.
