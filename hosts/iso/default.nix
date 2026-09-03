{ pkgs, lib, ... }:

{
  # Konfigurasi Live Media ISO Mandiri NEURONIX
  isoImage.isoBaseName = "neuronix-os";
  isoImage.volumeID = "NEURONIX_LIVE";
  isoImage.makeEfiBootable = true;
  isoImage.makeUsbBootable = true;

  networking.hostName = "neuronix-installer";

  # Live session user account (passwordless sudo enabled for live environment)
  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "video" "audio" ];
    description = "NEURONIX Live User";
  };
  security.sudo.wheelNeedsPassword = false;

  # Paket esensial di sesi Live ISO
  environment.systemPackages = with pkgs; [
    calamares
    gparted
    btrfs-progs
    efibootmgr
    pciutils
    usbutils
    git
    curl
  ];

  # Otomatis menjalankan Calamares Installer saat Live Session dibuka
  systemd.user.services.autostart-calamares = {
    description = "Autostart Calamares Installer on Live Session";
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.calamares}/bin/calamares";
      Restart = "no";
    };
  };

  system.stateVersion = "24.11";
}
