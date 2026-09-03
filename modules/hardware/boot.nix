{ pkgs, lib, ... }:

{
  boot.loader = {
    # Pilar 5: Batasi riwayat kernel bootloader maksimal 15 generasi (anti-overflow partisi ESP 1.0 GiB)
    systemd-boot = {
      enable = lib.mkDefault true;
      configurationLimit = 15;
      editor = false; # Keamanan: cegah modifikasi parameter kernel tanpa otentikasi
    };
    efi.canTouchEfiVariables = true;
    timeout = lib.mkDefault 5;
  };

  # Pilar 2 & 11: Sinkronisasi Dual-Boot Windows (Jam RTC Lokal & Deteksi Bootloader)
  time.hardwareClockInLocalTime = lib.mkDefault true;

  # Pilar 14: UEFI Boot Assessment Watchdog (Anti-mati total saat pemadaman listrik di tengah update)
  systemd.watchdog.runtimeTime = "30s";
  systemd.watchdog.rebootTime = "10min";

  # Pilar 12 & 10: Kernel Tuning (SteamOS vm.max_map_count & S0ix deep sleep)
  boot.kernelParams = [
    "mem_sleep_default=deep"
    "quiet"
    "splash"
    "loglevel=4"
  ];

  boot.kernel.sysctl = {
    # Standar SteamOS 3 / Fedora untuk gaming berat, Proton anti-cheat, dan IDE raksasa
    "vm.max_map_count" = 2147483642;
    "fs.file-max" = 2097152;
  };
}
