{ pkgs, lib, ... }:

{
  # Pilar 6: Inklusi lengkap seluruh firmware proprietary vendor (Wi-Fi, Bluetooth, GPU)
  hardware.enableAllFirmware = true;
  hardware.enableRedistributableFirmware = true;

  # Paket firmware lengkap untuk Realtek, Broadcom, Intel, Mediatek
  hardware.firmware = with pkgs; [
    linux-firmware
    wireless-regdb
  ];
}
