{ pkgs, ... }:

{
  # Git SSH & GPG Pinentry authentication under Wayland
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
    pinentryPackage = pkgs.pinentry-gnome3;
  };

  # Configured sudo security policies
  security.sudo = {
    enable = true;
    wheelNeedsPassword = true;
  };

  # PolKit for graphical privilege escalation
  security.polkit.enable = true;
}
