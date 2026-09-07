{ lib, pkgs, ... }:

{
  # Automated Intel and AMD CPU microcode updates (x86 only)
  hardware.cpu.intel.updateMicrocode = lib.mkDefault (pkgs.stdenv.hostPlatform.isx86);
  hardware.cpu.amd.updateMicrocode = lib.mkDefault (pkgs.stdenv.hostPlatform.isx86);
}
