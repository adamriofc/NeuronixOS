# NEURONIX Specification: Autonomous Update Policy & Storage Diet Lifecycle

> **Document ID:** `NRX-SPEC-007`  
> **Status:** Ratified & Implemented  
> **Domain:** System Maintenance, Desktop Notifications, Atomic Upgrades & Storage Retention  
> **Canonical References:** `modules/services/update.nix` & `modules/services/storage.nix`  

---

## 1. Executive Context & Architectural Philosophy

Traditional imperative Linux operating systems (e.g., Debian, Ubuntu, Arch Linux) execute system updates through destructive in-place file mutation, commonly introducing:
- Runtime fragility when shared libraries mutate beneath actively executing processes.
- The absence of an instantaneous, zero-loss rollback mechanism when regressions or upstream bugs occur.
- Unattended, disruptive update cycles that can break proprietary graphics drivers or interrupt critical workloads.

Conversely, a pure NixOS substrate records every configuration and software transition as an atomic, immutable **Generation** inside `/nix/store`. The inherent engineering challenge of this functional design is **uncontrolled storage accumulation (disk bloat)** if historical generations are left unmanaged.

**NEURONIX OS resolves both challenges through a harmonized dual architecture:**
1. **Gated Update Policy:** Combines lightweight upstream metadata monitoring in the background, desktop notification triggers, and staged atomic generation builds (`nixos-rebuild boot`) with zero execution disruption.
2. **4-Tier Storage Diet Subsystem:** Automates the reclamation of obsolete generations (> 14 days), unifies identical file content via hardlink inode deduplication, enforces dynamic emergency headroom floors (`min-free` / `max-free`), and dispatches physical SSD TRIM discards to host block devices.

---

## 2. System Update Architecture

### 2.1 Operational Update Modes

NEURONIX provides three declarative upgrade execution modes:

| Update Mode | Execution Semantics | Ideal Workload |
| :--- | :--- | :--- |
| **1. Staged Upgrade (Default)** | Fetches and builds target closures in `/nix/store` in the background, updates bootloader entries, and marks the generation active on subsequent reboot (`nixos-rebuild boot`). Zero disruption to active desktop sessions. | Daily workstations, developer laptops, enterprise production nodes. |
| **2. Instant Switch** | Builds the generation and immediately re-binds active runtime symlinks (`nixos-rebuild switch`). | Direct administrative tasks, rapid local configuration prototyping. |
| **3. Unattended Auto-Upgrade** | Systemd orchestrates scheduled rebuilds autonomously without user confirmation prompts. | Headless servers, automated continuous delivery build runners. |

### 2.2 Desktop Update Notifier Architecture
The `systemd.services.neuronix-update-check` service and `neuronix-update-check.timer` execute with minimal resource consumption:
1. Verify active network connectivity.
2. Query the latest commit hash from the upstream tracking branch (`https://github.com/adamriofc/neuronix.git`) via lightweight Git reference inspection (< 50 KB metadata).
3. If an upstream update is detected, dispatch a graphical desktop notification via `notify-send` across active desktop sessions (KDE Plasma, GNOME, Hyprland).

### 2.3 Declarative NixOS Configuration
Configured declaratively in `modules/services/update.nix`:

```nix
neuronix.services.updates = {
  enable = true;             # Enable update subsystem
  enableNotifier = true;     # Enable desktop notification daemon (Default: true)
  checkInterval = "daily";   # Upstream query frequency
  autoUpgrade = false;       # Fully autonomous unattended upgrade (Default: false)
  staged = true;             # Use staged nixos-rebuild boot (Default: true)
  allowReboot = false;       # Automatic reboot following auto-upgrade
  channel = "github:adamriofc/neuronix";
};
```

---

## 3. Storage Diet Lifecycle & Reclamation Engine

To prevent generation accumulation from exhausting disk capacity, NEURONIX enforces a 4-tier storage reclamation subsystem:

```text
┌─────────────────────────────────────────────────────────────┐
│       Tier 1: Scheduled Garbage Collection (nix.gc)         │
│       Unlinks generation symlinks older than 14 days        │
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│       Tier 2: Inode Hardlink Deduplication (nix.optimise)    │
│       Merges identical files to a single physical inode      │
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│       Tier 3: Dynamic Storage Guard (min-free / max-free)    │
│       Triggers emergency GC when disk space falls < 1 GiB   │
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│       Tier 4: Storage Controller TRIM Passthrough (fstrim)   │
│       Dispatches physical TRIM discards to SSD or hypervisor │
└─────────────────────────────────────────────────────────────┘
```

### 3.1 Declarative Storage Configuration
Configured in `modules/services/storage.nix`:

```nix
# Autonomous Storage Diet Policy
nix.gc = {
  automatic = lib.mkDefault true;
  dates = lib.mkDefault "weekly";
  options = lib.mkDefault "--delete-older-than 14d";
};

nix.optimise = {
  automatic = lib.mkDefault true;
  dates = [ "weekly" ];
};

nix.settings = {
  min-free = lib.mkDefault 1073741824; # 1 GiB Emergency Floor
  max-free = lib.mkDefault 3221225472; # 3 GiB Headroom Ceiling
};

services.fstrim = {
  enable = lib.mkDefault true;
  interval = "daily";
};
```

### 3.2 User Sovereignty (Manual Override)
All automated storage policies use `lib.mkDefault true`. Users requiring manual storage control can disable them declaratively in `/etc/nixos/configuration.nix`:

```nix
# Revert to full manual storage management
nix.gc.automatic = false;
nix.optimise.automatic = false;
services.fstrim.enable = false;
boot.tmp.cleanOnBoot = false;
```

### 3.3 Auxiliary Storage & Ephemeral Hygiene
Beyond the primary 4-tier diet engine, NEURONIX enforces 3 auxiliary hygiene automations:
1. **Systemd Journal Retention Ceiling:**
   Restricts `/var/log/journal` to a 500 MiB ceiling via `services.journald.extraConfig = "SystemMaxUse=500M\nSystemMaxFileSize=50M\nMaxRetentionSec=1month\nRuntimeMaxUse=100M\n";`.
2. **Ephemeral `/tmp` Directory Cleaning on Boot:**
   Guarantees `/tmp` is wiped clean upon each system boot via `boot.tmp.cleanOnBoot = lib.mkDefault true;`.
3. **Flatpak Unused Runtime Pruning:**
   Prunes orphaned Flatpak runtimes without active application consumers via `systemd.services.flatpak-prune-unused` and weekly timer `systemd.timers.flatpak-prune-unused`, also directly callable via `neuronix diet`.

---

## 4. Operational Interfaces (CLI, GUI, and MCP)

### 4.1 Command-Line Interface (`neuronix`)
- **Query Upstream Updates:**
  ```bash
  neuronix check-update
  ```
- **Staged System Upgrade (Recommended):**
  ```bash
  neuronix upgrade --staged
  ```
- **Instant System Switch:**
  ```bash
  neuronix upgrade --switch
  ```
- **Unified Storage Maintenance:**
  ```bash
  neuronix diet
  ```
- **Substrate Telemetry & Status:**
  ```bash
  neuronix status
  ```

### 4.2 Graphical Control Hub (NEURONIX Center)
- **`🔄 System Upgrade (Staged)`**: Initiates staged background rebuilds with interactive confirmation.
- **`🧹 Reclaim Storage (Diet)`**: Executes GC $\to$ Deduplication $\to$ TRIM pipeline in 1 click.
- **`↩ Atomic Rollback`**: Restores the operating system to the previous verified generation.

### 4.3 Model Context Protocol (MCP) Integration
- `neuronix_check_update`: Returns structured JSON representation of upstream git reference state.
- `neuronix_upgrade`: Dispatches staged or direct atomic system upgrades.
- `neuronix_diet`: Executes storage garbage collection, deduplication, and filesystem TRIM.
