{ pkgs, lib, ... }:

{
  # Integrated Flatpak & Flathub application marketplace
  services.flatpak.enable = true;

  # Inisialisasi Otomatis Remote Flathub saat Sistem Pertama Booting
  systemd.services.flatpak-repo-flathub = {
    description = "NEURONIX Flathub Repository Auto-Provisioning";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.flatpak}/bin/flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo";
      RemainAfterExit = true;
    };
  };

  # Declarative portals.conf mapping to prevent file chooser freeze under Wayland
  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-gtk
    ];
    config = {
      common = {
        default = [ "gtk" ];
        "org.freedesktop.impl.portal.FileChooser" = [ "gtk" ];
      };
      kde = {
        default = [ "kde" ];
        "org.freedesktop.impl.portal.FileChooser" = [ "kde" ];
      };
      gnome = {
        default = [ "gnome" ];
        "org.freedesktop.impl.portal.FileChooser" = [ "gnome" ];
      };
    };
  };

  # Paket pembantu Flatpak
  environment.systemPackages = with pkgs; [
    flatpak
  ];
}
