{ config, lib, pkgs, ... }:

let
  cfg = config.neuronix.services.updates;
in
{
  options.neuronix.services.updates = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable NEURONIX update management and notification subsystem.";
    };

    enableNotifier = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Send desktop notification when a new system generation/release is available.";
    };

    checkInterval = lib.mkOption {
      type = lib.types.str;
      default = "daily";
      description = "Systemd OnCalendar interval for checking upstream flake updates.";
    };

    autoUpgrade = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable unattended autonomous background system upgrades without manual intervention.";
    };

    staged = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Build updates in staged mode (nixos-rebuild boot) to prevent active session disruption.";
    };

    allowReboot = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Automatically reboot after unattended upgrade (only applicable if autoUpgrade is true).";
    };

    channel = lib.mkOption {
      type = lib.types.str;
      default = "github:adamriofc/neuronix";
      description = "Target flake URI for upstream release and package tree tracking.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Lightweight background update checker
    systemd.services.neuronix-update-check = lib.mkIf cfg.enableNotifier {
      description = "NEURONIX System Release & Flake Update Checker";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "neuronix-update-checker" ''
          set -euo pipefail
          # Verify internet connectivity
          if ! ${pkgs.iputils}/bin/ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; then
            exit 0
          fi
          
          # Check for update availability
          UPDATE_AVAILABLE=false
          CURRENT_LOCK="/etc/nixos/flake.lock"
          if [ -f "$CURRENT_LOCK" ]; then
            REMOTE_REV=$(${pkgs.git}/bin/git ls-remote --heads https://github.com/adamriofc/neuronix.git main 2>/dev/null | awk '{print $1}' || true)
            if [ -n "$REMOTE_REV" ]; then
              UPDATE_AVAILABLE=true
            fi
          fi

          if [ "$UPDATE_AVAILABLE" = "true" ]; then
            # Broadcast notification to all active graphical user sessions via notify-send
            for user_id in $(ls /run/user/ 2>/dev/null); do
              if [ -d "/run/user/$user_id" ]; then
                DBUS_ADDR="unix:path=/run/user/$user_id/bus"
                if [ -S "/run/user/$user_id/bus" ]; then
                  sudo -u "#$user_id" DBUS_SESSION_BUS_ADDRESS="$DBUS_ADDR" \
                    ${pkgs.libnotify}/bin/notify-send \
                    -i system-software-update \
                    -u normal \
                    "NEURONIX OS Update" \
                    "New system updates available. Open NEURONIX Center or run 'neuronix upgrade' to apply." || true
                fi
              fi
            done
          fi
        '';
      };
    };

    systemd.timers.neuronix-update-check = lib.mkIf cfg.enableNotifier {
      description = "Daily timer for NEURONIX update check";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.checkInterval;
        Persistent = true;
        RandomizedDelaySec = "30m";
      };
    };

    # Unattended Auto-Upgrade (if explicitly enabled by user)
    system.autoUpgrade = lib.mkIf cfg.autoUpgrade {
      enable = true;
      allowReboot = cfg.allowReboot;
      dates = cfg.checkInterval;
      flake = cfg.channel;
      operation = if cfg.staged then "boot" else "switch";
    };
  };
}
