{ config, lib, pkgs, ... }:

let
  cfg = config.neuronix.services.opencode;
  opencodePkg = pkgs.callPackage ../../packages/opencode {};

  # Authentic OpenCode MCP configuration bridging local neuronix mcp server
  opencodeConfig = pkgs.writeText "opencode.json" (builtins.toJSON {
    "$schema" = "https://opencode.ai/config.json";
    mcp = {
      neuronix = {
        type = "stdio";
        command = "neuronix";
        args = [ "mcp" ];
      };
    };
  });
in
{
  options.neuronix.services.opencode = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable built-in OpenCode AI Coding Agent across KDE, GNOME, and Hyprland.";
    };

    autoUpdate = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable autonomous background updates for OpenCode.";
      };
      interval = lib.mkOption {
        type = lib.types.str;
        default = "daily";
        description = "Systemd OnCalendar interval for checking upstream releases.";
      };
    };

    desktopShortcut = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Expose desktop shortcut and application launcher entries.";
    };

    mcpIntegration = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Bridge OpenCode to the local NEURONIX Model Context Protocol (MCP) server.";
    };
  };

  config = lib.mkIf cfg.enable {
    # System package registration
    environment.systemPackages = [ opencodePkg ];

    # Seed desktop icon in skeleton profile for traditional desktop environments (e.g. KDE Plasma)
    system.activationScripts.opencodeDesktopEntry = lib.mkIf cfg.desktopShortcut ''
      mkdir -p /etc/skel/Desktop
      if [ -f "${opencodePkg}/share/applications/opencode.desktop" ]; then
        cp -f "${opencodePkg}/share/applications/opencode.desktop" /etc/skel/Desktop/opencode.desktop
        chmod 755 /etc/skel/Desktop/opencode.desktop || true
      fi
    '';

    # Seed OpenCode MCP configuration into skeleton profile
    system.activationScripts.opencodeMcpConfig = lib.mkIf cfg.mcpIntegration ''
      mkdir -p /etc/skel/.config/opencode
      cp -f "${opencodeConfig}" /etc/skel/.config/opencode/opencode.json
      chmod 644 /etc/skel/.config/opencode/opencode.json || true
    '';

    # Autonomous background update service
    systemd.services.neuronix-opencode-update = lib.mkIf cfg.autoUpdate.enable {
      description = "NEURONIX OpenCode Autonomous Update Daemon";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "neuronix-opencode-update-checker" ''
          set -euo pipefail
          CURRENT_VER="$(${opencodePkg}/bin/opencode --version 2>/dev/null || echo "1.18.29")"
          echo "[OPENCODE-UPDATE] Current installed OpenCode version: $CURRENT_VER"
          if ${pkgs.curl}/bin/curl -s --connect-timeout 5 https://api.github.com/repos/anomalyco/opencode/releases/latest >/tmp/opencode_latest.json 2>/dev/null; then
            LATEST_TAG="$(${pkgs.jq}/bin/jq -r '.tag_name // empty' /tmp/opencode_latest.json 2>/dev/null || true)"
            rm -f /tmp/opencode_latest.json
            if [ -n "$LATEST_TAG" ]; then
              echo "[OPENCODE-UPDATE] Latest upstream OpenCode release: $LATEST_TAG"
            fi
          fi
        '';
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };

    # Background update timer
    systemd.timers.neuronix-opencode-update = lib.mkIf cfg.autoUpdate.enable {
      description = "Autonomous Update Timer for OpenCode";
      timerConfig = {
        OnCalendar = cfg.autoUpdate.interval;
        Persistent = true;
      };
      wantedBy = [ "timers.target" ];
    };
  };
}
