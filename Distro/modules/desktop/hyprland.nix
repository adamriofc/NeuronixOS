{ pkgs, ... }:

{
  # Desktop Environment: Hyprland Dynamic Tiling Wayland
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  environment.systemPackages = with pkgs; [
    waybar
    wofi
    dunst
    kitty
    grim
    slurp
    wl-clipboard
  ];
}
