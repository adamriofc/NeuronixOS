# NEURONIX OpenCode AI System Copilot Specification

**Component:** OpenCode Autonomous AI Copilot  
**Substrate Version:** 1.0.3  
**License:** Apache License 2.0  
**Integration:** Universal across KDE Plasma 6, GNOME, and Hyprland  

---

## 1. Abstract & Architectural Role

NEURONIX OS integrates **OpenCode** as its native, built-in AI system copilot. Operating as an intelligent bridge between the user and the declarative NixOS substrate, OpenCode transforms complex system administration, hardware management, and package orchestration into natural language commands and automated routines.

Unlike conventional Linux distributions where AI agents execute unconstrained imperative shell scripts that can corrupt root filesystems, OpenCode operates within the deterministic constraints of NEURONIX:
1. All changes are mediated through pure Nix expressions or validated via the local Model Context Protocol (MCP) server.
2. System modifications produce new NixOS profile generations with instant rollback capabilities (`neuronix undo`).
3. Proposed configurations can be evaluated inside an ephemeral in-memory Shadow Micro-VM (`neuronix try`) prior to host deployment.

---

## 2. Desktop Environment Integration

OpenCode is packaged natively (`packages/opencode/`) and exposed across all supported desktop environments:

| Desktop Environment | Display Server | Launcher Location | Interaction Pattern |
| :--- | :--- | :--- | :--- |
| **KDE Plasma 6** | Wayland / KWin | Application Launcher (Kickoff), KRunner (`Alt + Space`), Desktop Shortcut (`~/Desktop/opencode.desktop`) | Graphical terminal window (Kitty/Konsole) with rich ANSI styling. |
| **GNOME 47** | Wayland / Mutter | Application Grid, Dash to Dock | Full terminal window integration with Wayland clipboard bridging. |
| **Hyprland** | Dynamic Tiling Wayland | Wofi, Rofi, Anyrun, keybind `SUPER + Return` | Launches dynamically inside default tiling terminal instance. |

The XDG desktop entry (`opencode.desktop`) is installed into `/run/current-system/sw/share/applications/` and seeded into `/etc/skel/Desktop/` during system activation.

---

## 3. Interactive Commands & Tooling

OpenCode provides an interactive command loop and command-line arguments:

```bash
# Launch interactive session
opencode

# Query real-time hardware, kernel, and generation state
opencode status

# Execute upstream update synchronization check
opencode update

# Verify derivation in pure nixpkgs closure
opencode verify ripgrep

# Evaluate configuration in in-memory Shadow Micro-VM
opencode try ./configuration.nix

# Query system manual chapters directly via CLI
opencode manual cli
```

### Interactive Internal Commands

When running in interactive mode (`opencode interactive`), the following built-in commands are available:
- `/status`: Displays active Linux kernel, CPU/GPU telemetry, memory pressure, and generation index.
- `/manual [topic]`: Renders system manual chapters directly inside the interactive session without leaving the chat loop.
- `/verify <package>`: Evaluates whether a package derivation builds cleanly against the nixpkgs closure.
- `/try [file.nix]`: Spawns a transient QEMU micro-VM in `/dev/shm` to verify proposed configurations.
- `/diet`: Invokes `neuronix diet` to purge unreferenced store paths and issue SSD discard commands.
- `/rollback`: Reverts the operating system to the previous generation via atomic symlink swap.
- `/update`: Queries upstream distribution channels and validates release checksums.
- `/help`: Displays available commands and usage guidance.
- `/exit`: Terminates the interactive copilot session.

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
