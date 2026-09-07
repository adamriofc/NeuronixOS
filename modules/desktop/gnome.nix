{ pkgs, ... }:

{
  # Desktop Environment: GNOME Wayland (Tokyo Cyber Palette & Gesture Navigation)
  services.xserver.enable = true;
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  environment.systemPackages = with pkgs; [
    gnome-software # Toko Aplikasi GUI GNOME Software
    gnome-tweaks
    adw-gtk3
  ];
}
