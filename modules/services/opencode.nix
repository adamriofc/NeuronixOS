{ config, lib, pkgs, ... }:

let
  cfg = config.neuronix.services.opencode;
  opencodePkg = pkgs.callPackage ../../packages/opencode {};
in
{
  options.neuronix.services.opencode = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable built-in OpenCode AI System Copilot across KDE, GNOME, and Hyprland.";
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

    # Autonomous background update service
    systemd.services.neuronix-opencode-update = lib.mkIf cfg.autoUpdate.enable {
      description = "NEURONIX OpenCode Autonomous Update Daemon";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${opencodePkg}/bin/opencode update";
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
