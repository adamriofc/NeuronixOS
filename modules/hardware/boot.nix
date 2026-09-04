{ pkgs, lib, config ? {}, ... }:

{
  options = {
    neuronix.hardware.kernelFlavor = lib.mkOption {
      type = lib.types.enum [ "default" "zen" "lts" "latest" "hardened" ];
      default =
        if builtins.pathExists /etc/neuronix/kernel-profile then
          let
            raw = lib.strings.trim (builtins.readFile /etc/neuronix/kernel-profile);
          in
            if builtins.elem raw [ "default" "zen" "lts" "latest" "hardened" ] then raw else "default"
        else "default"; # default, zen, lts, latest, hardened
      description = "Linux kernel profile flavor (zen: gaming/low-latency, lts: long-term, latest: bleeding-edge, hardened: high-security)";
    };
  };

  config = {
    boot.kernelPackages = lib.mkDefault (
      if (config.neuronix.hardware.kernelFlavor or "default") == "zen" then pkgs.linuxPackages_zen
      else if (config.neuronix.hardware.kernelFlavor or "default") == "lts" then pkgs.linuxPackages_lts
      else if (config.neuronix.hardware.kernelFlavor or "default") == "latest" then pkgs.linuxPackages_latest
      else if (config.neuronix.hardware.kernelFlavor or "default") == "hardened" then pkgs.linuxPackages_hardened
      else pkgs.linuxPackages
    );

    boot.loader = {
      # Bootloader generation limit (15 generations on 1.0 GiB ESP)
      systemd-boot = {
        enable = lib.mkDefault true;
        configurationLimit = 15;
        editor = false; # Security: prevent unauthenticated kernel parameter modifications
      };
      efi.canTouchEfiVariables = true;
      timeout = lib.mkDefault 5;
    };

    # Dual-boot Windows synchronization (RTC local time & UEFI boot discovery)
    time.hardwareClockInLocalTime = lib.mkDefault true;

    # Ephemeral /tmp Directory Hygiene
    # Purge stale temporary files in /tmp during system boot
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
  };
}
