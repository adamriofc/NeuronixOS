{ pkgs, lib, ... }:

{
  # Konfigurasi Live Media ISO Mandiri NEURONIX
  image.baseName = lib.mkForce "neuronix-os";
  isoImage.volumeID = "NEURONIX_LIVE";
  isoImage.makeEfiBootable = true;
  isoImage.makeUsbBootable = true;
  boot.zfs.forceImportRoot = false;

  # Optimize squashfs compression and live media closure size to stay within 2 GiB asset limits
  isoImage.squashfsCompression = "zstd -Xcompression-level 19 -b 1048576";
  documentation.enable = lib.mkForce false;
  documentation.nixos.enable = lib.mkForce false;
  documentation.man.enable = lib.mkForce false;
  documentation.info.enable = lib.mkForce false;
  documentation.doc.enable = lib.mkForce false;

  networking.hostName = "neuronix-installer";

  # Live session user account (passwordless sudo enabled for live environment)
  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "video" "audio" ];
    description = "NEURONIX Live User";
    home = "/home/nixos";
    shell = pkgs.bash;
    initialHashedPassword = lib.mkForce null;
    initialPassword = "neuronix";
  };
  security.sudo.wheelNeedsPassword = false;

  # Auto-login for live session (bypass GDM login screen)
  services.displayManager.autoLogin = {
    enable = true;
    user = "nixos";
  };

  # Ensure GDM display manager is enabled
  services.displayManager.gdm.enable = true;

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
    (writeShellScriptBin "neuronix-install-engine" ''
      exec ${bash}/bin/bash /etc/calamares/scripts/neuronix-install-engine.sh "$@"
    '')
  ];

  # Ensure GNOME desktop is available for live session
  services.xserver.enable = true;
  services.desktopManager.gnome.enable = true;

  # Provision declarative Calamares configuration and installation engine into Live Media
  environment.etc."calamares/modules".source = ../../installer/calamares/modules;
  environment.etc."calamares/branding/neuronix".source = ../../installer/calamares/branding/neuronix;
  environment.etc."calamares/settings.conf".source = ../../installer/calamares/settings.conf;
  environment.etc."calamares/scripts/neuronix-install-engine.sh" = {
    source = ../../installer/scripts/neuronix-install-engine.sh;
    mode = "0755";
  };
  environment.etc."neuronix/modules".source = ../../modules;
  environment.etc."neuronix/packages".source = ../../packages;
  environment.etc."neuronix/version.nix".source = ../../version.nix;

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
