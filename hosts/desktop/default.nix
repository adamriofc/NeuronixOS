{ pkgs, lib, ... }:

{
  networking.hostName = lib.mkDefault "neuronix-box";

  # User akun dasar (dikonfigurasi oleh Calamares saat instalasi)
  users.users.neuronix = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "video" "audio" ];
    description = "NEURONIX Default User";
  };

  # Default root filesystem fallback for pure flake evaluation
  fileSystems."/" = lib.mkDefault {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  # System state version
  system.stateVersion = "24.11";
}
