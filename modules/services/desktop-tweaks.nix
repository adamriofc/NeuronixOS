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

  # NEURONIX Branding, Artwork & First-Boot Onboarding Integration
  environment.etc = {
    "neuronix/artwork/wallpaper.svg".source = ../../artwork/wallpapers/neuronix-cyber-neural-dark.svg;
    "neuronix/artwork/badge.svg".source = ../../artwork/branding/neuronix-badge.svg;
    "neuronix/artwork/logo.png".source = ../../artwork/branding/neuronix-logo.png;
    "neuronix/artwork/symbol.png".source = ../../artwork/branding/neuronix-symbol.png;
    "neuronix/artwork/banner.png".source = ../../artwork/branding/neuronix-banner.png;
    "xdg/autostart/neuronix-welcome.desktop".source = ../../packages/neuronix-center/neuronix-welcome.desktop;
  };
}
