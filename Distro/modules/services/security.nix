{ pkgs, ... }:

{
  # Pilar 27: Otentikasi Git SSH & GPG Pinentry Terpadu di Wayland
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
    pinentryPackage = pkgs.pinentry-gnome3;
  };

  # Keamanan sudo terkonfigurasi
  security.sudo = {
    enable = true;
    wheelNeedsPassword = true;
  };

  # PolicyKit untuk otentikasi GUI
  security.polkit.enable = true;
}
