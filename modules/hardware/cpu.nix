{ lib, ... }:

{
  # Pilar 26: Pembaruan Otomatis Microcode CPU Intel & AMD (Perlindungan Spectre/Zenbleed/Downfall)
  hardware.cpu.intel.updateMicrocode = lib.mkDefault true;
  hardware.cpu.amd.updateMicrocode = lib.mkDefault true;
}
