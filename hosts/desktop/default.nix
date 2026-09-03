{ pkgs, lib, ... }:

{
  networking.hostName = lib.mkDefault "neuronix-box";

  # User akun dasar (dikonfigurasi oleh Calamares saat instalasi)
  users.users.neuronix = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "video" "audio" ];
    description = "NEURONIX Default User";
  };

  # Versi state sistem
  system.stateVersion = "24.11";
}
