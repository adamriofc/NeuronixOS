{ pkgs, ... }:

{
  # Desktop Environment: GNOME Wayland (Tokyo Cyber Palette & Gesture Navigation)
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;

  environment.systemPackages = with pkgs; [
    gnome-software # Toko Aplikasi GUI GNOME Software
    gnome-tweaks
    adw-gtk3
  ];
}
