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
          # Arm the active watchdog timer
          systemctl start neuronix-boot-sentinel-watchdog.timer 2>/dev/null || true
        '';
      };
    };

    # Active assessment watchdog timer (triggers fallback if not confirmed in time)
    systemd.timers.neuronix-boot-sentinel-watchdog = {
      description = "NEURONIX Boot-Sentinel Assessment Watchdog Timer";
      wantedBy = [ "basic.target" ];
      timerConfig = {
        OnActiveSec = cfg.assessmentTimeout;
        Unit = "neuronix-boot-fallback.service";
      };
    };

    # Phase 2: Post-graphical confirmation (disarms watchdog and records last-known-good)
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
          # Disarm the watchdog timer
          systemctl stop neuronix-boot-sentinel-watchdog.timer 2>/dev/null || true
          if [ -L /nix/var/nix/profiles/system ]; then
            CURRENT_GEN=$(readlink /nix/var/nix/profiles/system | sed -n 's/.*system-\([0-9]*\)-link/\1/p')
            if [ -n "$CURRENT_GEN" ]; then
              echo "$CURRENT_GEN" > /var/lib/neuronix/last-known-good
              echo "[SENTINEL] Generation #$CURRENT_GEN successfully confirmed. Marked as last-known-good."
              rm -f /run/neuronix/booting-generation || true
            fi
          fi
        '';
      };
    };

    # Phase 3: Emergency Fallback Rollback Handler (Converges on Rollback Core & Journal)
    systemd.services.neuronix-boot-fallback = {
      description = "NEURONIX Emergency Boot Fallback & Self-Healing Rollback";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "neuronix-sentinel-fallback" ''
          set -euo pipefail
          mkdir -p /var/log/neuronix /run/neuronix
          LOG_FILE="/var/log/neuronix/boot-fallback.log"
          echo "[$(date -u)] [SENTINEL-FALLBACK] Emergency boot failure or assessment timeout detected!" >> "$LOG_FILE"

          # Disarm timer to prevent re-trigger loop
          systemctl stop neuronix-boot-sentinel-watchdog.timer 2>/dev/null || true

          LAST_GOOD=""
          if [ -f /var/lib/neuronix/last-known-good ]; then
            LAST_GOOD=$(cat /var/lib/neuronix/last-known-good | tr -d '[:space:]')
          fi

          echo "[SENTINEL-FALLBACK] Invoking transactional rollback core towards last-known-good: #$LAST_GOOD" >> "$LOG_FILE"

          # Execute rollback via unified Python core with OperationLock, TransactionJournal, and postcondition assurance
          PYTHON_BIN="${pkgs.python3}/bin/python3"
          if [ -x "$PYTHON_BIN" ]; then
            $PYTHON_BIN -c "
          import sys
          sys.path.insert(0, '/run/current-system/sw/lib/python3/site-packages')
          sys.path.insert(0, '/etc/nixos/packages/neuronix-core')
          try:
              from neuronix_core.rollback import execute_rollback
              from neuronix_core.journal import TransactionJournal
              journal = TransactionJournal()
              target_gen = int('$LAST_GOOD') if '$LAST_GOOD'.isdigit() else None
              tx_id = journal.start_transaction('emergency_sentinel_rollback', {'target': target_gen})
              success, return_code, output = execute_rollback(target_generation=target_gen)
              if success:
                  journal.commit_transaction(tx_id, {'outcome': 'restored', 'return_code': return_code, 'output': output})
                  print('[SENTINEL-FALLBACK] Transaction committed successfully.')
                  sys.exit(0)
              else:
                  journal.abort_transaction(tx_id, f'Rollback failed (code {return_code}): {output}')
                  print(f'[SENTINEL-FALLBACK] Rollback error (code {return_code}): {output}')
                  sys.exit(1)
          except Exception as e:
              print(f'[SENTINEL-FALLBACK] Core exception: {e}')
              sys.exit(1)
          " >> "$LOG_FILE" 2>&1 || true
          fi

          # Verify postcondition before rebooting
          RESTORED_GEN=$(readlink /nix/var/nix/profiles/system | sed -n 's/.*system-\([0-9]*\)-link/\1/p' || echo "")
          if [ -n "$RESTORED_GEN" ] && [ "$RESTORED_GEN" = "$LAST_GOOD" ]; then
            echo "[SENTINEL-FALLBACK] Verified restored generation #$RESTORED_GEN matches last-known-good via transactional rollback. Requesting clean reboot." >> "$LOG_FILE"
            systemctl reboot
          else
            echo "[SENTINEL-FALLBACK] Critical: Transactional rollback verification failed (expected: #$LAST_GOOD, found: #$RESTORED_GEN). Preserving system state to prevent unjournaled drift." >> "$LOG_FILE"
          fi
        '';
      };
    };
  };
}
