{ config, lib, pkgs, ... }:

let
  cfg = config.neuronix.tuning;
in
{
  options.neuronix.tuning = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable deterministic workload tuning engine (gaming, battery, audio-daw, balanced).";
    };

    defaultProfile = lib.mkOption {
      type = lib.types.str;
      default = "balanced";
      description = "Default startup workload profile (gaming, battery, audio-daw, balanced).";
    };
  };

  config = lib.mkIf cfg.enable {
    # System tooling required for sandboxing and tuning
    environment.systemPackages = with pkgs; [
      bubblewrap
    ];

    # Apply initial tuning state on boot
    systemd.services.neuronix-workload-tuning = {
      description = "NEURONIX Workload Tuning Initialization";
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-modules-load.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "neuronix-tuning-init" ''
          set -euo pipefail
          STATE_FILE="/var/lib/neuronix/active-workload-profile"
          mkdir -p /var/lib/neuronix
          if [ ! -f "$STATE_FILE" ]; then
            echo "${cfg.defaultProfile}" > "$STATE_FILE"
          fi
          # Ensure SteamOS standard max_map_count is applied
          if [ -w /proc/sys/vm/max_map_count ]; then
            echo 2147483642 > /proc/sys/vm/max_map_count || true
          fi
        '';
      };
    };
  };
}
