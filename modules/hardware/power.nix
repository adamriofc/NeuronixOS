{ pkgs, lib, ... }:

{
  # Pilar 10: Manajemen Daya Modern Standby S0ix & Pengendalian Suhu Laptop
  services.power-profiles-daemon.enable = true;
  services.thermald.enable = lib.mkDefault true;

  # Pilar 19: Kontrol Batas Pengisian Baterai Laptop 80% (Perpanjang Umur Baterai)
  # Menyediakan layanan systemd pendukung untuk menulis ambang batas ke sysfs
  systemd.services.neuronix-battery-threshold = {
    description = "NEURONIX Battery Health Threshold Controller (80% Limit)";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "set-battery-limit" ''
        # Dukungan universal: ASUS, Lenovo Ideapad/ThinkPad, Dell, Framework
        for bat in /sys/class/power_supply/BAT*; do
          if [ -f "$bat/charge_control_limit_max" ]; then
            echo 80 > "$bat/charge_control_limit_max" 2>/dev/null || true
          elif [ -f "$bat/charge_stop_threshold" ]; then
            echo 80 > "$bat/charge_stop_threshold" 2>/dev/null || true
          fi
        done
      '';
    };
  };

  # Utilitas pemantau baterai
  environment.systemPackages = with pkgs; [
    acpi
    powertop
  ];
}
