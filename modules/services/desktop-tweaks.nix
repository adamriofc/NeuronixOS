{ pkgs, lib, config ? {}, ... }:

{
  options = {
    neuronix.desktop.inputMethodProfile = lib.mkOption {
      type = lib.types.enum [ "standard" "cjk-full" "minimal" ];
      default = "standard";
      description = "Input method language engine profile (standard: fcitx5-gtk, cjk-full: adds mozc/hangul/chinese, minimal: none)";
    };
  };

  config = {
    # Wayland HiDPI / 4K Fractional Scaling environment flags
    # Menjamin aplikasi Electron (VS Code, Spotify, Discord) tajam (pixel-crisp)
    environment.sessionVariables = {
      NIXOS_OZONE_WL = "1";
      MOZ_ENABLE_WAYLAND = "1";
      ELECTRON_OZONE_PLATFORM_HINT = "auto";
    };

    # Multilingual input method support (Fcitx5 Wayland Frontend)
    i18n.inputMethod = lib.mkIf ((config.neuronix.desktop.inputMethodProfile or "standard") != "minimal") {
      enable = true;
      type = "fcitx5";
      fcitx5.waylandFrontend = true;
      fcitx5.addons = with pkgs; [
        fcitx5-gtk
      ] ++ (lib.optionals ((config.neuronix.desktop.inputMethodProfile or "standard") == "cjk-full") [
        fcitx5-mozc
        fcitx5-hangul
        fcitx5-chinese-addons
      ]);
    };

    # Tipografi Terkurasi Berkualitas Tinggi
    fonts.packages = with pkgs; [
      inter
      jetbrains-mono
      fira-code
      noto-fonts
      noto-fonts-cjk-sans
      (if pkgs ? noto-fonts-color-emoji then pkgs.noto-fonts-color-emoji else pkgs.noto-fonts-emoji)
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
  };
}
