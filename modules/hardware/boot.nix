{ pkgs, lib, config ? {}, ... }:

{
  options = {
    neuronix.hardware.kernelFlavor = lib.mkOption {
      type = lib.types.enum [ "default" "zen" "lts" "latest" "hardened" ];
      default = "default";
      description = "Linux kernel profile flavor (zen: gaming/low-latency, lts: long-term, latest: bleeding-edge, hardened: high-security)";
    };

    neuronix.power.sleepMode = lib.mkOption {
      type = lib.types.enum [ "auto" "deep" "s2idle" ];
      default = "auto";
      description = "Target system sleep mode (auto: kernel default, deep: S3, s2idle: modern standby)";
    };

    neuronix.boot.windowsDualBoot = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Synchronize RTC in local time for Windows dual-boot consistency";
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

    # Dual-boot Windows synchronization (RTC local time when explicitly enabled)
    time.hardwareClockInLocalTime = lib.mkDefault (config.neuronix.boot.windowsDualBoot or false);

    # Ephemeral /tmp Directory Hygiene
    # Purge stale temporary files in /tmp during system boot
    boot.tmp.cleanOnBoot = lib.mkDefault true;

    # UEFI Boot Assessment Watchdog (power-loss protection during update)
    systemd.settings.Manager = {
      RuntimeWatchdogSec = "30s";
      RebootWatchdogSec = "10min";
    };

    # Kernel tuning (SteamOS vm.max_map_count and adaptive sleep)
    boot.kernelParams = [
      "quiet"
      "splash"
      "loglevel=4"
    ] ++ (lib.optional ((config.neuronix.power.sleepMode or "auto") == "deep") "mem_sleep_default=deep")
      ++ (lib.optional ((config.neuronix.power.sleepMode or "auto") == "s2idle") "mem_sleep_default=s2idle");

    boot.kernel.sysctl = {
      # SteamOS 3 / Fedora standard for high-concurrency gaming, Proton, and large IDEs
      "vm.max_map_count" = 2147483642;
      "fs.file-max" = 2097152;
    };
  };
}
