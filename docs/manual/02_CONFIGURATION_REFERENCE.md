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
