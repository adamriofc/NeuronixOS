{ pkgs, lib, ... }:

{
  # Full redistributable firmware bundle (Wi-Fi, Bluetooth, GPU)
  hardware.enableAllFirmware = true;
  hardware.enableRedistributableFirmware = true;

  # Complete firmware bundle for Realtek, Broadcom, Intel, and MediaTek
  hardware.firmware = with pkgs; [
    linux-firmware
    wireless-regdb
  ];
}
