# Chapter 2: Declarative Configuration Reference

## 1. Declarative Module Hierarchy

All NEURONIX OS subsystems are controlled through the structured `neuronix.*` NixOS option hierarchy. These options can be declared in `/etc/nixos/configuration.nix` or composed within custom Nix Flakes.

---

## 2. Option Specifications

### 2.1 Boot & Kernel Management (`neuronix.hardware.boot`)

Controls the active Linux kernel package, bootloader policies, and hardware console timers.

| Option Path | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `neuronix.hardware.boot.kernelFlavor` | enum: `["default", "zen", "lts", "latest", "hardened"]` | `"default"` | Selects Linux kernel optimization profile. `zen` enables low-latency desktop scheduling. |
| `neuronix.hardware.boot.generationLimit` | integer | `15` | Maximum number of past bootloader generations retained in EFI boot menu. |
| `neuronix.hardware.boot.cleanOnBoot` | boolean | `true` | Automatically flushes `/tmp` memory mounts upon bootloader handoff. |

Example:
```nix
neuronix.hardware.boot = {
  kernelFlavor = "zen";
  generationLimit = 20;
};
```

### 2.2 Storage & Autonomous Diet (`neuronix.services.storage`)

Controls Btrfs maintenance timers, storage garbage collection, and dynamic disk guards.

| Option Path | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `neuronix.services.storage.enable` | boolean | `true` | Enables baseline storage optimization policies. |
| `neuronix.services.storage.trimInterval` | string | `"daily"` | Systemd timer interval for issuing VirtIO and physical NVMe SSD TRIM discards. |
| `neuronix.services.storage.btrfsBalance` | boolean | `true` | Enables monthly autonomous Btrfs subvolume balancing. |

### 2.3 Memory Pressure Shield (`neuronix.services.memoryShield`)

Manages high-load RAM exhaustion defense, zram pools, and Out-Of-Memory daemon thresholds.

| Option Path | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `neuronix.services.memoryShield.enable` | boolean | `true` | Enables ZRAM Zstandard compression pool and systemd-oomd integration. |
| `neuronix.services.memoryShield.zramPercent` | integer | `50` | Percentage of total physical RAM allocated to Zstandard compressed swap space. |
| `neuronix.services.memoryShield.psiMonitoring` | boolean | `true` | Enables Linux kernel Pressure Stall Information telemetry monitoring. |

### 2.4 Autonomous Updates (`neuronix.services.updates`)

Configures upstream git repository tracking, background checks, and desktop notifications.

| Option Path | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `neuronix.services.updates.enable` | boolean | `true` | Activates background update check daemons. |
| `neuronix.services.updates.enableNotifier`| boolean | `true` | Sends desktop notifications when upstream releases are published. |
| `neuronix.services.updates.checkInterval` | string | `"daily"` | Systemd OnCalendar interval for checking upstream git commits. |
| `neuronix.services.updates.staged` | boolean | `true` | Builds updates in background and applies on reboot without session disruption. |

### 2.5 OpenCode AI Copilot (`neuronix.services.opencode`)

Manages built-in autonomous AI assistant and MCP integration.

| Option Path | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `neuronix.services.opencode.enable` | boolean | `true` | Installs OpenCode system package and desktop menu entries. |
| `neuronix.services.opencode.mcpIntegration`| boolean | `true` | Bridges OpenCode directly to the local NEURONIX MCP server over stdio. |
| `neuronix.services.opencode.autoUpdate` | boolean | `true` | Enables autonomous background updates for OpenCode copilot. |
| `neuronix.services.opencode.desktopShortcut`| boolean | `true` | Creates launcher icon in application menus and desktop skeleton. |

---

## 3. Applying Declarative Changes

After modifying `/etc/nixos/configuration.nix`, apply changes with zero downtime:

```bash
# Instant switch (live symlink activation)
sudo nixos-rebuild switch

# Staged upgrade (prepared for next boot)
sudo nixos-rebuild boot

# Revert immediately if unsatisfied
neuronix undo
```

---

## 4. Software Installation & Distro Transition Guide

NEURONIX OS accommodates users transitioning from conventional Linux distributions (Ubuntu, Debian, Fedora) and Arch Linux through a tiered application delivery model.

### 4.1 System Packages (Nixpkgs Declarative)
To install system-wide utilities and packages permanently, add them to `environment.systemPackages` in `/etc/nixos/configuration.nix`:

```nix
environment.systemPackages = with pkgs; [
  git
  htop
  ripgrep
  neovim
  vlc
];
```

Apply modifications atomically:
```bash
sudo nixos-rebuild switch
# or rollback immediately if undesirable
neuronix undo
```

### 4.2 Ephemeral Software Execution (Zero-Pollution)
Run or test software on-demand without permanently altering system state or installing globally:
```bash
# Execute application once and discard
nix run nixpkgs#htop

# Open transient shell with tools loaded in RAM
nix-shell -p ffmpeg p7zip
```

### 4.3 Desktop Graphical Applications (Flatpak & Flathub)
For desktop productivity, multimedia, gaming, and proprietary applications (Spotify, Steam, Discord, Chrome, Obsidian), NEURONIX auto-provisions Flathub out-of-the-box:
- Visual Store: Search and install directly via **KDE Discover** or **GNOME Software**.
- CLI Execution:
  ```bash
  flatpak install flathub com.spotify.Client
  ```
- Storage Maintenance: Unused runtimes are pruned weekly by `systemd.timers.flatpak-prune-unused` or on-demand via `neuronix clean`.

### 4.4 Unpatched Generic Linux Binaries (Global nix-ld)
Unlike standard NixOS which fails on pre-compiled foreign ELF executables, NEURONIX enables `programs.nix-ld.enable = true` globally. Unpatched dynamic ELF executables, proprietary CLI utilities, CUDA toolchains, and AppImages execute directly out-of-the-box without manual patchelf intervention.

### 4.5 Foreign Distro Compatibility: Arch AUR & Debian PPA (Distrobox)
To run specialized packages exclusive to the Arch User Repository (AUR) or Ubuntu PPAs without polluting the declarative host, run an integrated OCI container with native Wayland, PipeWire, and GPU acceleration:
```bash
# Spawn Arch Linux environment
distrobox create --name arch --image archlinux:latest
distrobox enter arch
# Inside container: access pacman, makepkg, and AUR helpers (yay / paru)

# Export GUI application to host desktop launcher
distrobox-export --app <app-name>
```
