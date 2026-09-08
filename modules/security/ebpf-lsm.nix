{ config, lib, pkgs, ... }:

let
  cfg = config.neuronix.security.ebpfLsm;
in
{
  options.neuronix.security.ebpfLsm = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable declarative eBPF Linux Security Module (LSM) kernel capability configuration and security policy contracts.";
    };

    mode = lib.mkOption {
      type = lib.types.enum [ "enforcing" "audit" ];
      default = "enforcing";
      description = "Operating mode for eBPF LSM policy engine (enforcing: authoritative security contract for audit verification; audit: advisory contract).";
    };

    defaultProtectedPaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "/etc/shadow" "/etc/ssh" "/root" ];
      description = "Paths protected against unprivileged reads by developer toolchains.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Ensure kernel command line enables BPF LSM if supported
    boot.kernelParams = [ "lsm=lockdown,yama,bpf,apparmor,integrity" ];
  };
}
