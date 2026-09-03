{ pkgs, ... }:

{
  # Desktop Environment: KDE Plasma 6 (Wayland Default)
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };

  services.desktopManager.plasma6.enable = true;

  # Paket Terkurasi KDE Plasma 6
  environment.systemPackages = with pkgs.kdePackages; [
    kate
    kcalc
    dolphin
    spectacle
    ark
    plasma-systemmonitor
    discover # Toko Aplikasi GUI KDE Discover
  ];
}
