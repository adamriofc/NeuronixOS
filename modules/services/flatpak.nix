{ pkgs, lib, ... }:

{
  # Integrated Flatpak & Flathub application marketplace
  services.flatpak.enable = true;

  # Automatic provisioning of Flathub remote on first boot
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

  # Periodic pruning of unused Flatpak runtimes (orphaned runtimes)
  systemd.services.flatpak-prune-unused = {
    description = "NEURONIX Flatpak Unused Runtime Pruner";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "flatpak-prune-unused" ''
        if [ -x "${pkgs.flatpak}/bin/flatpak" ]; then
          ${pkgs.flatpak}/bin/flatpak uninstall --unused -y 2>/dev/null || true
        fi
      '';
    };
  };

  systemd.timers.flatpak-prune-unused = {
    description = "Weekly timer for orphaned Flatpak runtime pruning";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "weekly";
      Persistent = true;
      RandomizedDelaySec = "1h";
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

  # Flatpak runtime packages
  environment.systemPackages = with pkgs; [
    flatpak
  ];
}
