{ lib, ... }:

{
  # Automated Intel and AMD CPU microcode updates
  hardware.cpu.intel.updateMicrocode = lib.mkDefault true;
  hardware.cpu.amd.updateMicrocode = lib.mkDefault true;
}
