{ pkgs, lib, ... }:

{
  boot.loader = {
    # Bootloader generation limit (15 generations on 1.0 GiB ESP)
    systemd-boot = {
      enable = lib.mkDefault true;
      configurationLimit = 15;
      editor = false; # Keamanan: cegah modifikasi parameter kernel tanpa otentikasi
    };
    efi.canTouchEfiVariables = true;
    timeout = lib.mkDefault 5;
  };

  # Dual-boot Windows synchronization (RTC local time & UEFI boot discovery)
  time.hardwareClockInLocalTime = lib.mkDefault true;

  # Ephemeral /tmp Directory Hygiene
  # Membersihkan seluruh file sementara yang tertinggal di /tmp saat sistem booting
  boot.tmp.cleanOnBoot = lib.mkDefault true;

  # UEFI Boot Assessment Watchdog (power-loss protection during update)
  systemd.watchdog.runtimeTime = "30s";
  systemd.watchdog.rebootTime = "10min";

  # Kernel tuning (SteamOS vm.max_map_count and S0ix deep sleep)
  boot.kernelParams = [
    "mem_sleep_default=deep"
    "quiet"
    "splash"
    "loglevel=4"
  ];

  boot.kernel.sysctl = {
    # SteamOS 3 / Fedora standard for high-concurrency gaming, Proton, and large IDEs
    "vm.max_map_count" = 2147483642;
    "fs.file-max" = 2097152;
  };
}
