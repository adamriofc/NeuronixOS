{ pkgs, lib, ... }:

{
  imports = [
    ./manual.nix
  ];

  # Konfigurasi Inti Nix & Flakes
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
    trusted-users = [ "root" ];
    substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  # Proprietary licensed package support (Steam, NVIDIA, Spotify)
  nixpkgs.config.allowUnfree = true;

  # Aktivasi Global nix-ld: Eksekusi biner FHS Linux konvensional tanpa error
  programs.nix-ld.enable = true;

  # Lingkungan CLI & Perkakas Esensial Sistem
  environment.systemPackages = with pkgs; [
    git
    curl
    wget
    fastfetch
    htop
    btop
    btrfs-progs
    pciutils
    usbutils
    util-linux
    jq
    ripgrep
    fd
    which
  ];

  # Prompt Terminal Sadar Generasi Sistem
  programs.bash.promptInit = ''
    # Deteksi nomor generasi aktif NixOS
    CURRENT_GEN=$(readlink /nix/var/nix/profiles/system | sed -n 's/.*system-\([0-9]*\)-link/\1/p')
    if [ -n "$CURRENT_GEN" ]; then
      GEN_TAG="\[\033[1;36m\][Gen #$CURRENT_GEN]\[\033[0m\] "
    else
      GEN_TAG=""
    fi
    PS1="$GEN_TAG\[\033[1;32m\]\u@\h\[\033[0m\]:\[\033[1;34m\]\w\[\033[0m\]\$ "
  '';

  # Timezone & Lokalisasi Default
  time.timeZone = lib.mkDefault "Asia/Jakarta";
  i18n.defaultLocale = lib.mkDefault "en_US.UTF-8";

  # Integrasi Shell Default
  programs.bash.enableCompletion = true;
}
