{ pkgs, lib, ... }:

{
  networking.hostName = lib.mkDefault "neuronix-box";

  # User akun dasar (dikonfigurasi oleh Calamares saat instalasi)
  users.users.neuronix = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "video" "audio" ];
    description = "NEURONIX Default User";
  };

  # System state version
  system.stateVersion = "24.11";
}
