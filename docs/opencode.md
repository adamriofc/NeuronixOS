# NEURONIX OpenCode AI System Specification

**Component:** Authentic Upstream OpenCode CLI/TUI  
**Upstream Project:** [anomalyco/opencode](https://github.com/anomalyco/opencode) ([opencode.ai](https://opencode.ai))  
**Version:** 1.18.29  
**License:** MIT  
**Integration:** Universal across KDE Plasma 6, GNOME, and Hyprland  

---

## 1. Abstract & Architectural Role

NEURONIX OS integrates the authentic upstream **OpenCode** CLI/TUI as its default, pre-installed terminal AI coding agent. OpenCode is an open-source, terminal-native AI agent designed to run directly in the terminal, featuring both an interactive Terminal User Interface (TUI) and a non-interactive Command-Line Interface (CLI).

In NEURONIX OS, OpenCode operates within the deterministic constraints of the NixOS substrate:
1. Native integration with the local Model Context Protocol (MCP) server (`neuronix mcp`), providing immediate access to system inspection, verification, and atomic rollback tools.
2. Ambient system awareness via `/etc/neuronix/SYSTEM_PROMPT.md` and `/etc/neuronix/manual/` references.
3. Completely unaltered upstream binary packaged natively with zero mocks or synthetic wrappers.

---

## 2. Desktop Environment Integration

OpenCode is packaged natively (`packages/opencode/`) and exposed across all supported desktop environments:

| Desktop Environment | Display Server | Launcher Location | Interaction Pattern |
| :--- | :--- | :--- | :--- |
| **KDE Plasma 6** | Wayland / KWin | Application Launcher (Kickoff), KRunner (`Alt + Space`), Desktop Shortcut (`~/Desktop/opencode.desktop`) | Launches the authentic interactive TUI in default terminal window. |
| **GNOME 47** | Wayland / Mutter | Application Grid, Dash to Dock | Launches the authentic interactive TUI with clipboard integration. |
| **Hyprland** | Dynamic Tiling Wayland | Wofi, Rofi, Anyrun, keybind `SUPER + Return` | Launches dynamically inside default tiling terminal instance. |

The XDG desktop entry (`opencode.desktop`) is installed into `/run/current-system/sw/share/applications/` and seeded into `/etc/skel/Desktop/` during system activation.

---

## 3. Interactive Commands & Tooling

OpenCode provides an interactive Terminal User Interface (TUI) and flexible CLI commands:

```bash
# Launch interactive TUI session
opencode

# Start OpenCode inside a specific project path
opencode /path/to/project

# Execute prompt directly via non-interactive CLI mode
opencode run "inspect flake.nix and summarize inputs"

# Manage Model Context Protocol (MCP) connections
opencode mcp list
opencode mcp add neuronix

# Inspect AI providers, credentials, and models
opencode models
opencode providers

# Upgrade or check OpenCode releases
opencode upgrade --help
```

### Native Model Context Protocol (MCP) Integration

OpenCode natively supports the Model Context Protocol. When `mcpIntegration` is enabled, NEURONIX automatically provisions the MCP client configuration in `~/.config/opencode/opencode.json`:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "neuronix": {
      "type": "stdio",
      "command": "neuronix",
      "args": ["mcp"]
    }
  }
}
```

Through this bridge, OpenCode accesses:
- `neuronix_status`: Query active kernel, CPU/GPU, memory pressure, and generation state.
- `neuronix_diet`: Purge stale store generations and reclaim storage.
- `neuronix_verify`: Evaluate package derivations hermetically.
- `neuronix_undo`: Atomically roll back to prior system generations.
- `neuronix_manual`: Query system manual chapters directly via structured tool calls.

---

## 4. Autonomous Background Update Engine

To ensure users always have the latest capabilities and security mitigations without requiring manual package rebuilds, OpenCode includes an autonomous background update daemon:

```text
[ systemd.timers.neuronix-opencode-update ]
                  │
                  │ (Triggers on daily calendar interval)
                  ▼
[ systemd.services.neuronix-opencode-update ]
  1. Waits for network connectivity (network-online.target).
  2. Queries official NEURONIX distribution channel.
  3. Validates release integrity via SHA256 verification.
  4. Synchronizes binaries and updates active execution pointer.
```

### Systemd Invariants:
- **Type:** `oneshot` (terminates immediately upon completion, consuming zero memory during idle states).
- **Interval:** Configurable via `neuronix.services.opencode.autoUpdate.interval` (default: `"daily"`).
- **Persistent:** `true` (if the computer was suspended or powered off during the scheduled window, the check triggers immediately upon boot).

---

## 5. Autonomous System Grounding & Reference Hub

OpenCode operates with native awareness of NEURONIX system architecture without requiring manual prompt crafting or user intervention:

1. **Automatic Directives Ingestion:** Upon launch, OpenCode detects `/etc/neuronix/manual/10_AI_AGENT_REFERENCE.md` (and the root symlink `/etc/neuronix/SYSTEM_PROMPT.md`). It automatically injects the system directives into the active session context before user input is accepted.
2. **Zero-Command Grounding:** Users never need to issue `neuronix manual` or type `/manual` to force the AI model into compliance. All natural language prompts are processed through the lens of declarative NixOS principles (preventing imperatively harmful actions like `apt-get`, `pacman -S`, or unrecorded root file modifications).
3. **MCP Protocol Integration:** OpenCode natively leverages the local MCP server (`neuronix mcp`), accessing system manual resources under `neuronix://manual/*` and calling tools like `neuronix_diet` or `neuronix_manual` on demand.

---

## 6. Declarative Module Configuration

OpenCode is controlled declaratively in `/etc/nixos/configuration.nix` via `modules/services/opencode.nix`:

```nix
{ config, pkgs, ... }:

{
  # Built-in OpenCode AI Copilot Configuration
  neuronix.services.opencode = {
    enable = true;                 # Default: true (active out-of-the-box)
    autoUpdate = {
      enable = true;               # Default: true (autonomous background updates)
      interval = "daily";          # Interval string ("daily", "weekly", etc.)
    };
    desktopShortcut = true;        # Generates desktop and application menu entries
    mcpIntegration = true;         # Bridges to local NEURONIX MCP JSON-RPC server
  };
}
```

---

## 7. Zero-Residue Removal Workflow

NEURONIX adheres strictly to the principle of user autonomy. If a user chooses not to use OpenCode:

1. Set `enable = false;` in `/etc/nixos/configuration.nix`:
   ```nix
   neuronix.services.opencode.enable = false;
   ```
   *(Or toggle the feature off in NEURONIX Center).*

2. Rebuild the system generation:
   ```bash
   sudo nixos-rebuild switch
   ```

3. Run storage reclamation:
   ```bash
   neuronix diet
   ```

**Result:** The OpenCode binary, background systemd service, background timer, desktop entries, and all associated dependencies are completely eliminated from the active system generation with zero residual files.
