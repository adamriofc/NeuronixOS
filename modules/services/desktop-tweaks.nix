{ pkgs, ... }:

{
  # Wayland HiDPI / 4K Fractional Scaling environment flags
  # Menjamin aplikasi Electron (VS Code, Spotify, Discord) tajam (pixel-crisp)
  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    MOZ_ENABLE_WAYLAND = "1";
    ELECTRON_OZONE_PLATFORM_HINT = "auto";
  };

  # Multilingual input method support (Fcitx5 Wayland Frontend)
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.waylandFrontend = true;
    fcitx5.addons = with pkgs; [
      fcitx5-gtk
      fcitx5-mozc
      fcitx5-hangul
      fcitx5-chinese-addons
    ];
  };

  # Tipografi Terkurasi Berkualitas Tinggi
  fonts.packages = with pkgs; [
    inter
    jetbrains-mono
    fira-code
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-emoji
  ];
}
