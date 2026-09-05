# Technical Specification: Distro Onboarding, System Diagnostics, Quickstart App Catalog & Declarative Kernel Management (08_ONBOARDING_AND_DISTRO_EXPERIENCE)

> **Document ID:** `NRX-SPEC-008`  
> **Status:** Ratified & Active  
> **Target Release:** NEURONIX OS v1.0.3+  
> **Subcomponents:** `neuronix welcome`, `neuronix doctor`, `neuronix quickstart`, `neuronix kernel`, `artwork/`, `modules/hardware/boot.nix`, `packages/neuronix-center/`  
> **Verification:** Suite 23 Test Contracts (1,028 Total Assertions / 100% Pass)

---

## 1. Executive Context & Architectural Philosophy

EndeavourOS gained broad community adoption in the Linux ecosystem through polished user-facing onboarding and system utility tools: a first-boot welcome wizard (`eos-welcome`), a log and diagnostics aggregator (`eos-log-tool`), a rapid application installer (`eos-quickstart`), and a kernel manager (`akm`). However, beneath these conveniences, traditional imperative Arch-based distributions exhibit foundational engineering vulnerabilities:

1. **Imperative Fragility:** Installing applications, switching kernels, or querying diagnostics relies on imperative package managers (`pacman`, `yay`) that mutate the live filesystem in place. These operations lack atomic transaction boundaries and instantaneous zero-loss rollback mechanisms.
2. **Privacy Exposure:** Conventional log export tools frequently upload or dump unredacted system telemetry, exposing private IPv4/IPv6 addresses, hardware MAC addresses, local user account identifiers, and hostnames.
3. **Storage & State Corruption Risks:** Manual kernel swapping and non-atomic initramfs regeneration risk unbootable system states if a build is interrupted or if external kernel modules fail during compilation.

**NEURONIX OS embraces these UX ergonomics while systematically superseding them** through its **pure-functional NixOS substrate**, **declarative configuration model**, **instantaneous zero-disruption rollback defense**, and **privacy-preserving sanitization engine**.

---

## 2. Subcomponent Architecture

```text
+---------------------------------------------------------------------------------------+
|                                    NEURONIX OS                                        |
|                          LAYER 4: USER EXPERIENCE & POLISH                            |
+---------------------------------------------------------------------------------------+
        |                             |                            |
        v                             v                            v
 [First-Boot Welcome]        [System Doctor & Audit]      [Quickstart App Hub]
  - neuronix-welcome.desktop  - Automated Data Sanitizer   - Curated Flatpak Apps
  - GUI & CLI Hybrid Wizard   - [REDACTED-IP/MAC] Masking  - Zero Nix Store Mutation
  - Auto-launch Controller    - GitHub Issue Ready Output  - Flathub Direct Pipeline
        |                             |                            |
        +-----------------------------+----------------------------+
                                      |
                                      v
                        [Declarative Kernel Manager]
                         - neuronix.hardware.kernelFlavor
                         - [default, zen, lts, latest, hardened]
                         - Staged Rollback Defense
```

---

## 3. Subcomponent 1: Interactive First-Boot Onboarding (`neuronix welcome`)

### 3.1 Behavioral Specification
- **Desktop Auto-launch:** Managed via the standard XDG autostart entry `/etc/xdg/autostart/neuronix-welcome.desktop`, triggering automatically on a new user's initial graphical login.
- **Hybrid Dual-Mode Execution (GUI + CLI):**
  - In graphical sessions (Wayland/X11), launches the native Qt/GTK control interface: `neuronix-center --welcome`.
  - In terminal, SSH, or headless environments (or when invoked with `--cli`), renders a responsive ANSI terminal guide providing system status and navigation shortcuts.
- **Autostart Toggle:** Supports `--disable-autostart` and `--enable-autostart` flags, allowing users to configure autostart preferences via standard user-level XDG overrides without mutating declarative system configurations.

---

## 4. Subcomponent 2: System Diagnostics & Privacy-Preserving Audit (`neuronix doctor`)

### 4.1 Diagnostic Checks & System Audit
Gathers comprehensive system health telemetry without requiring elevated root privileges:
1. **Substrate Metadata:** Distribution release, kernel version, CPU architecture, uptime, active generation index, and total generations stored in `/nix/store`.
2. **Hardware Telemetry:** CPU processor model, core/thread count, physical memory (RAM) allocation, Swap metrics, and GPU device detection.
3. **Storage Health:** Filesystem consumption for `/` and `/nix/store`, alongside operational states of core background timers (`neuronix-auto-diet.timer`, `neuronix-security-audit.timer`, `neuronix-auto-update.timer`).
4. **Kernel Dmesg Ring Buffer:** Captures the 15 most recent error-level events from the kernel ring buffer for proactive hardware and driver fault diagnosis.

### 4.2 Privacy-Preserving Sanitization Pipeline
Before diagnostic output is written to disk or streamed to standard output, the report undergoes strict deterministic sanitization:
- Local system usernames are masked as `<sanitized-user>`.
- System hostnames are masked as `<sanitized-host>`.
- IPv4 and IPv6 network addresses are replaced with `[REDACTED-IP]`.
- Network interface hardware MAC addresses are replaced with `[REDACTED-MAC]`.

Output is written by default to `/tmp/neuronix-doctor.md` in GitHub-flavored Markdown, pre-formatted for direct submission to the [NEURONIX Issue Tracker](https://github.com/adamriofc/neuronix/issues/new). The tool also supports a `--json` flag for machine consumption and Model Context Protocol (MCP) server integration.

---

## 5. Subcomponent 3: Curated Quickstart Application Hub (`neuronix quickstart`)

### 5.1 Declarative Isolation & Flathub Integration
Unlike imperative distro installers that write unmanaged binaries directly to the root partition, `neuronix quickstart` utilizes **Flatpak via Flathub**, enabled declaratively in `modules/services/flatpak.nix`. This architecture guarantees:
- `/nix/store` remains **100% immutable**, reproducible, and protected against unmanaged dependency mutations.
- Desktop applications execute within isolated bubblewrap sandboxes with discrete runtime permissions.

### 5.2 Curated Catalog Registry
- **Web Browsers:** Brave (`com.brave.Browser`), Chrome (`com.google.Chrome`), Firefox (`org.mozilla.firefox`).
- **Development Tools:** VS Code (`com.visualstudio.code`), VSCodium (`com.vscodium.codium`), Postman (`com.getpostman.Postman`), DBeaver (`io.dbeaver.DBeaverCommunity`).
- **Communication:** Discord (`com.discordapp.Discord`), Telegram (`org.telegram.desktop`), Slack (`com.slack.Slack`).
- **Multimedia:** VLC (`org.videolan.VLC`), OBS Studio (`com.obsproject.Studio`), Spotify (`com.spotify.Client`), GIMP (`org.gimp.GIMP`).
- **Productivity:** LibreOffice (`org.libreoffice.LibreOffice`), Obsidian (`md.obsidian.Obsidian`).

CLI Operations:
```bash
neuronix quickstart list
neuronix quickstart install brave
neuronix quickstart search <keyword>
```

---

## 6. Subcomponent 4: Declarative Kernel Flavor Manager (`neuronix kernel`)

### 6.1 Declarative NixOS Module Option
Defined in `modules/hardware/boot.nix`:
```nix
neuronix.hardware.kernelFlavor = lib.mkOption {
  type = lib.types.enum [ "default" "zen" "lts" "latest" "hardened" ];
  default = "default";
  description = "Linux kernel package flavor selection for NEURONIX OS.";
};
```

### 6.2 Kernel Flavor Specifications
| Flavor | Nix Package Binding | Primary Characteristics | Target Workload |
| :--- | :--- | :--- | :--- |
| `default` | `pkgs.linuxPackages` | Verified upstream NixOS stable kernel | Servers, general computing, standard laptops |
| `zen` | `pkgs.linuxPackages_zen` | Low-latency scheduler, interactive responsiveness | Gaming, real-time audio, desktop workstations |
| `lts` | `pkgs.linuxPackages_lts` | Long-Term Support, maximum driver stability | Mission-critical workstations, enterprise deployments |
| `latest` | `pkgs.linuxPackages_latest` | Bleeding-edge upstream mainline kernel | Latest generation CPU/GPU hardware architectures |
| `hardened` | `pkgs.linuxPackages_hardened` | Strict memory protection, exploit mitigations | High-security environments, hardened nodes |

Kernel transitions are executed via **Staged Upgrades** (`neuronix upgrade --staged`), staging the target closure for the subsequent bootloader entry without interrupting the running kernel session. If hardware regressions occur, instant recovery is guaranteed via bootloader rollback or `neuronix undo`.

---

## 7. Subcomponent 5: Visual Identity & 4K Artwork System

1. **Canonical Distro Logo (3D Mondrian Neural Master):**
   - Master Source Path: `artwork/branding/neuronix-logo.png` (2048x2048 master high-resolution emblem featuring a 3D Mondrian primary-color construct with bold typography).
   - Multi-Resolution Icons: Generated at 1024x1024, 512x512, 256x256, 128x128, and 64x64 (`artwork/branding/neuronix-logo-*.png`).
   - Declarative Exposure: Linked via `environment.etc` to `/etc/neuronix/artwork/logo.png`.
2. **Distro Symbol & Application Icon:**
   - Source Path: `artwork/branding/neuronix-symbol.png` (512x512 square cropped 3D "N" emblem for desktop application launchers, taskbar, and avatars).
   - Declarative Exposure: Linked via `environment.etc` to `/etc/neuronix/artwork/symbol.png`.
3. **Official GitHub Header Banner:**
   - Source Path: `artwork/branding/neuronix-banner.png` (1920x640 widescreen header banner seamlessly unified with the authentic black patterned grid directly from the master logo, featuring clean typography and architectural pillars without bounding wrappers).
   - Declarative Exposure: Linked via `environment.etc` to `/etc/neuronix/artwork/banner.png`.
4. **Default 4K UHD Wallpaper:**
   - Source Path: `artwork/wallpapers/neuronix-cyber-neural-dark.svg`
   - Resolution: 3840x2160 (lossless scalable SVG, cyber-neural motif featuring deep cyan gradients, neural node geometry, and high-frequency circuit traces).
   - System Symlink: Declaratively linked to `/etc/neuronix/artwork/wallpaper.svg`.
5. **Distro Branding Emblem Badge:**
   - Source Path: `artwork/branding/neuronix-badge.svg` (512x512 vector emblem).

---

## 8. Quality Gates & Test Verification

The features specified in this document are verified by **Suite 23** in the NEURONIX automated test harness:
- Syntax parsing and option validation for `boot.nix` and `desktop-tweaks.nix`.
- SVG schema validity for 4K wallpaper and XDG autostart desktop entry syntax.
- Data sanitization regex assertions for `neuronix doctor` (username, hostname, IP, MAC).
- Non-blocking execution and graceful exit codes for `neuronix welcome`, `quickstart`, and `kernel`.
- JSON-RPC 2.0 schema validation for MCP tools `neuronix_doctor` and `neuronix_quickstart_list`.

The complete NEURONIX test harness executes **1,028 assertions** across 25 QA master suites, 19 distro suites, and 13 standalone gates, maintaining a **100% pass rate**.
