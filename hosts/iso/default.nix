{ pkgs, lib, ... }:

{
  # Konfigurasi Live Media ISO Mandiri NEURONIX
  image.baseName = lib.mkForce "neuronix-os";
  isoImage.volumeID = "NEURONIX_LIVE";
  isoImage.makeEfiBootable = true;
  isoImage.makeUsbBootable = true;
  boot.zfs.forceImportRoot = false;
  # Live media boots through iso-image.nix, never the installed-host bootloader.
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.efi.canTouchEfiVariables = lib.mkForce false;
  isoImage.edition = "neuronix";
  neuronix.desktop = {
    enable = true;
    live.enable = true;
    live.user = "nixos";
  };

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
    # Live media only. Installed accounts use authenticated greetd login.
    initialHashedPassword = lib.mkForce "";
  };
  security.sudo.wheelNeedsPassword = false;

  # Preserve installer requirements without upstream desktop/autostart packages.
  security.polkit.enablePkexecWrapper = true;
  programs.partition-manager.enable = true;
  i18n.supportedLocales = [ "all" ];

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
    glibcLocales
    openssl
    (writeShellScriptBin "neuronix-install-engine" ''
      exec ${bash}/bin/bash /etc/calamares/scripts/neuronix-install-engine.sh "$@"
    '')
  ];

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

  # Complete source layout for offline generation of the installed host flake.
  # Relative module/package references must resolve after leaving the live ISO.
  environment.etc."neuronix/installer-source/modules".source = ../../modules;
  environment.etc."neuronix/installer-source/packages".source = ../../packages;
  environment.etc."neuronix/installer-source/artwork".source = ../../artwork;
  environment.etc."neuronix/installer-source/docs".source = ../../docs;
  environment.etc."neuronix/installer-source/bin".source = ../../bin;
  environment.etc."neuronix/installer-source/data".source = ../../data;
  environment.etc."neuronix/installer-source/src".source = ../../src;
  environment.etc."neuronix/installer-source/version.nix".source = ../../version.nix;

  # NEURONIX Artwork & Branding (explicit copy for ISO)
  environment.etc."neuronix/artwork/wallpaper.svg".source = ../../artwork/wallpapers/neuronix-cyber-neural-dark.svg;
  environment.etc."neuronix/artwork/logo.png".source = ../../artwork/branding/neuronix-logo.png;
  environment.etc."neuronix/artwork/symbol.png".source = ../../artwork/branding/neuronix-symbol.png;
  environment.etc."neuronix/artwork/banner.png".source = ../../artwork/branding/neuronix-banner.png;
  environment.etc."neuronix/artwork/badge.svg".source = ../../artwork/branding/neuronix-badge.svg;

  system.stateVersion = "24.11";
}
