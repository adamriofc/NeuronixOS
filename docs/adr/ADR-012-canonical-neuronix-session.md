# ADR-012: Canonical Neuronix Session and Live/Installed Experience Parity

## Status
**Accepted** for the session composition correction. Build, graphical VM boot, and physical hardware qualification are separate evidence gates and remain **UNVERIFIED** until executed against the changed image.

## Context & Problem Statement
The live ISO and reference desktops selected GNOME, while the installation engine defaulted to KDE. Neuronix applications were installed within those environments, but no canonical Neuronix session owned the boot-to-desktop experience. Passing component and installer contract tests did not establish graphical integration or consistent first-boot behavior.

Conductor's current Rust surface is a POSIX TTY application. It cannot start a Wayland window by itself. NEURONIX Center is a separate graphical maintenance utility; relabeling it as Conductor would conceal this implementation boundary.

## Architectural Decision
1. **One canonical composition:** `modules/desktop/neuronix.nix` supplies the Neuronix profile to the ISO, installed reference configurations, and installer-generated targets. KDE, GNOME, and Hyprland remain explicit compatibility choices.
2. **Reuse the graphical substrate:** greetd starts the Neuronix session on Sway/Wayland. NixOS continues to own kernel, hardware, services, package management, and atomic generations. No new compositor is introduced.
3. **Truthful Conductor entry point:** The session starts `conductor --interactive` in foot. foot owns the graphical terminal window; Conductor supplies its terminal surface. Center stays reachable as a distinct maintenance GUI.
4. **Live/installed boundary:** Live media auto-logs in as `nixos` and exposes the on-demand Install action. Installed systems authenticate the configured user, support locking, and omit live installer actions and auto-login.
5. **Independent capability runtime:** Visual session startup and shutdown do not redefine skill authority or manage external agent jobs. Conductor's systemd socket broker, typed skill contracts, delegation policy, and evidence receipts retain their existing boundaries.
6. **Shared interaction contract:** `Mod+Return` opens a terminal, `Mod+Shift+c` opens Conductor, `Mod+c` opens Center, `Mod+Space` opens the launcher, and `Mod+Shift+e` logs out. Live sessions expose `Mod+i` for installation; installed sessions expose `Mod+Shift+l` for locking. `Mod` is Super/Windows.

## Consequences
- **Positive:** The default live and installed experiences share a versioned composition rather than inheriting unrelated desktop defaults. The installer becomes an application within the live experience.
- **Trade-off:** Sway, foot, panel, notifications, authentication, portals, and XWayland compatibility need integration testing. Center currently requires XWayland. This composition does not satisfy future standalone graphical Conductor requirements by itself.
- **Compatibility:** Optional desktop profiles remain available. Runtime behavior on GPUs, HiDPI displays, suspend/resume, and non-US keyboards requires corresponding hardware evidence.
- **Recovery:** Closing Conductor leaves the graphical session available. The terminal and launcher shortcuts provide recovery paths; installed users can log out or switch to a console. A previously working NixOS generation remains a boot recovery option.

## Verification & Evidence
Source and installer tests must verify profile selection, the live-only installer boundary, installed authentication, and consistent module imports. Nix evaluation must reject unintended default GNOME/GDM or KDE/SDDM activation in the canonical profile.

An actual ISO must then be booted in a VM, installed onto that VM's disposable virtual disk, and rebooted into the installed session. A controlled update and rollback must retain Neuronix identity. The same display and input checks must be repeated on reference hardware before claiming physical qualification. Follow the [graphical qualification runbook](../operations/11_graphical_session_qualification.md).

An available ISO, working `/dev/kvm`, successful component tests, or the presence of desktop packages is not evidence that the ISO reached the expected graphical session. Record missing stages as **UNVERIFIED**, never as a graphical PASS.
