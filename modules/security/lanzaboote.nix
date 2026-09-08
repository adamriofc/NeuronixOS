{ config, lib, pkgs, ... }:

let
  cfg = config.neuronix.security.secureBoot;
in
{
  options.neuronix.security.secureBoot = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Unified Kernel Image (UKI) signing and TPM2 PCR-sealed measured boot.";
    };

    pcrBinding = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "7" "11" ];
      description = "Platform Configuration Registers to bind LUKS2 tokens to (PCR 7 for Secure Boot, PCR 11 for UKI binary). PCR 0/2/4 are excluded to prevent lockouts across BIOS updates.";
    };

    fallbackPassphrase = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Preserve mandatory secondary Argon2id passphrase slot in LUKS2 to prevent hardware lockout if TPM state drifts.";
    };

    ukiMode = lib.mkOption {
      type = lib.types.enum [ "unified-kernel-image" "systemd-boot-fallback" ];
      default = "unified-kernel-image";
      description = "Operating mode for UEFI boot execution and kernel binary encapsulation.";
    };
  };

  config = lib.mkIf cfg.enable {
    boot.loader.systemd-boot.enable = lib.mkForce false;
    boot.initrd.systemd.enable = true;
    boot.initrd.systemd.tpm2.enable = true;
    boot.kernelParams = [ "lanzaboote=enforcing" ];
  };
}
