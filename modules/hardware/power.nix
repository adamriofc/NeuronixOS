{ pkgs, lib, ... }:

{
  # Modern Standby S0ix power management and thermal regulation
  services.power-profiles-daemon.enable = true;
  services.thermald.enable = lib.mkDefault true;

  # Battery charge threshold control (80% conservation ceiling)
  # Systemd service writing battery charge threshold to sysfs
  systemd.services.neuronix-battery-threshold = {
    description = "NEURONIX Battery Health Threshold Controller (80% Limit)";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "set-battery-limit" ''
        set -eu
        shopt -s nullglob
        batteries=(/sys/class/power_supply/BAT*)

        if [ ''${#batteries[@]} -eq 0 ]; then
          echo "BATTERY_THRESHOLD: UNSUPPORTED (No battery power supply detected)"
          exit 0
        fi

        applied_count=0
        failed_count=0

        for bat in "''${batteries[@]}"; do
          target_file=""
          if [ -w "$bat/charge_control_end_threshold" ]; then
            target_file="$bat/charge_control_end_threshold"
          elif [ -w "$bat/charge_control_limit_max" ]; then
            target_file="$bat/charge_control_limit_max"
          elif [ -w "$bat/charge_stop_threshold" ]; then
            target_file="$bat/charge_stop_threshold"
          fi

          if [ -n "$target_file" ]; then
            if echo 80 > "$target_file" 2>/dev/null; then
              val="$(cat "$target_file" 2>/dev/null || echo "")"
              if [ "$val" = "80" ]; then
                echo "BATTERY_THRESHOLD: APPLIED on $target_file (limit set to 80%)"
                applied_count=$((applied_count + 1))
              else
                echo "BATTERY_THRESHOLD: FAILED verification on $target_file (expected 80, read '$val')" >&2
                failed_count=$((failed_count + 1))
              fi
            else
              echo "BATTERY_THRESHOLD: FAILED writing to $target_file" >&2
              failed_count=$((failed_count + 1))
            fi
          else
            echo "BATTERY_THRESHOLD: UNSUPPORTED sysfs interface on $bat (charge_control_end_threshold / charge_control_limit_max / charge_stop_threshold not writable)"
          fi
        done

        if [ "$failed_count" -gt 0 ]; then
          echo "BATTERY_THRESHOLD: FAILED ($failed_count battery interfaces failed to set or verify)" >&2
          exit 1
        fi

        if [ "$applied_count" -gt 0 ]; then
          echo "BATTERY_THRESHOLD: SUCCESS ($applied_count battery interfaces active at 80%)"
          exit 0
        else
          echo "BATTERY_THRESHOLD: UNSUPPORTED (Hardware does not expose writable charge threshold sysfs knobs)"
          exit 0
        fi
      '';
    };
  };

  # Utilitas pemantau baterai
  environment.systemPackages = with pkgs; [
    acpi
    powertop
  ];
}
