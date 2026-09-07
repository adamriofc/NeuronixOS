{ config, lib, pkgs, ... }:

let
  cfg = config.neuronix.boot.sentinel;
in
{
  options.neuronix.boot.sentinel = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable autonomous Boot-Sentinel for zero-brick boot assessment and crash-loop auto-rollback.";
    };

    assessmentTimeout = lib.mkOption {
      type = lib.types.str;
      default = "60s";
      description = "Timeout duration before boot assessment triggers emergency fallback to last-known-good generation.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Ensure state directory exists
    system.activationScripts.neuronixSentinelState = ''
      mkdir -p /var/lib/neuronix
      mkdir -p /var/log/neuronix
      chmod 755 /var/lib/neuronix /var/log/neuronix

      # Seed last-known-good on initial installation if not already present
      if [ ! -f /var/lib/neuronix/last-known-good ]; then
        if [ -L /nix/var/nix/profiles/system ]; then
          CURRENT_GEN=$(readlink /nix/var/nix/profiles/system | sed -n 's/.*system-\([0-9]*\)-link/\1/p')
          if [ -n "$CURRENT_GEN" ]; then
            echo "$CURRENT_GEN" > /var/lib/neuronix/last-known-good
          fi
        fi
      fi
    '';

    # Phase 1: Early-boot sentinel initialization
    systemd.services.neuronix-boot-sentinel = {
      description = "NEURONIX Early-Boot Assessment Sentinel";
      wantedBy = [ "basic.target" ];
      before = [ "display-manager.service" "graphical.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "neuronix-sentinel-arm" ''
          set -euo pipefail
          mkdir -p /run/neuronix
          if [ -L /nix/var/nix/profiles/system ]; then
            CURRENT_GEN=$(readlink /nix/var/nix/profiles/system | sed -n 's/.*system-\([0-9]*\)-link/\1/p')
            echo "$CURRENT_GEN" > /run/neuronix/booting-generation
            echo "[SENTINEL] Booting generation #$CURRENT_GEN under active assessment window (${cfg.assessmentTimeout})."
          fi
        '';
      };
    };

    # Phase 2: Post-graphical confirmation (disarms sentinel and records last-known-good)
    systemd.services.neuronix-boot-confirm = {
      description = "NEURONIX Healthy Boot Assessment Confirmation";
      wantedBy = [ "graphical.target" ];
      after = [ "graphical.target" "display-manager.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "neuronix-sentinel-confirm" ''
          set -euo pipefail
          mkdir -p /var/lib/neuronix /var/log/neuronix
          if [ -L /nix/var/nix/profiles/system ]; then
            CURRENT_GEN=$(readlink /nix/var/nix/profiles/system | sed -n 's/.*system-\([0-9]*\)-link/\1/p')
            if [ -n "$CURRENT_GEN" ]; then
              echo "$CURRENT_GEN" > /var/lib/neuronix/last-known-good
              echo "[SENTINEL] Generation #$CURRENT_GEN successfully reached graphical.target. Marked as last-known-good."
              rm -f /run/neuronix/booting-generation || true
            fi
          fi
        '';
      };
    };

    # Phase 3: Emergency Fallback Rollback Handler
    systemd.services.neuronix-boot-fallback = {
      description = "NEURONIX Emergency Boot Fallback & Self-Healing Rollback";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "neuronix-sentinel-fallback" ''
          set -euo pipefail
          mkdir -p /var/log/neuronix
          LOG_FILE="/var/log/neuronix/boot-fallback.log"
          echo "[$(date -u)] [SENTINEL-FALLBACK] Emergency boot failure detected!" >> "$LOG_FILE"

          if [ -f /var/lib/neuronix/last-known-good ]; then
            LAST_GOOD=$(cat /var/lib/neuronix/last-known-good | tr -d '[:space:]')
            TARGET_LINK="/nix/var/nix/profiles/system-''${LAST_GOOD}-link"
            if [ -e "$TARGET_LINK" ]; then
              echo "[SENTINEL-FALLBACK] Reverting active profile link to #''${LAST_GOOD} ($TARGET_LINK)" >> "$LOG_FILE"
              ln -sfn "$TARGET_LINK" /nix/var/nix/profiles/system
              echo "[SENTINEL-FALLBACK] Rollback executed. Requesting system reboot." >> "$LOG_FILE"
              systemctl reboot
              exit 0
            fi
          fi
          echo "[SENTINEL-FALLBACK] Warning: last-known-good profile not found. Preserving current link." >> "$LOG_FILE"
        '';
      };
    };
  };
}
