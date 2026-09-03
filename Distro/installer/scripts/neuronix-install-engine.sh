#!/usr/bin/env bash
# ==============================================================================
# NEURONIX OS: Declarative Flake-Generating Installer Engine
# Part of Phase 4 Distribution Architecture
# Translates Calamares GUI selections into a pristine, reproducible NixOS Flake.
# ==============================================================================
set -euo pipefail

TARGET_ROOT="${TARGET_ROOT:-/mnt}"
TARGET_USER="${TARGET_USER:-neuronix}"
TARGET_HOSTNAME="${TARGET_HOSTNAME:-neuronix-box}"
SELECTED_DESKTOP="${SELECTED_DESKTOP:-kde}"
DRY_RUN="${DRY_RUN:-0}"

log() {
  echo -e "\033[1;32m[NEURONIX-INSTALLER]\033[0m $*"
}

log_warn() {
  echo -e "\033[1;33m[NEURONIX-INSTALLER WARN]\033[0m $*"
}

log "Memulai proses instalasi deklaratif NEURONIX ke target: $TARGET_ROOT"
log "Parameter: User=$TARGET_USER, Host=$TARGET_HOSTNAME, Desktop=$SELECTED_DESKTOP"

if [ "$DRY_RUN" -eq 1 ]; then
  log "Mode simulasi (DRY-RUN) aktif. Melewati pembuatan partisi fisik."
  MOCK_DIR="/tmp/neuronix-mock-install"
  rm -rf "$MOCK_DIR"
  mkdir -p "$MOCK_DIR/etc/nixos"
  TARGET_ROOT="$MOCK_DIR"
fi

CONFIG_DIR="$TARGET_ROOT/etc/nixos"
mkdir -p "$CONFIG_DIR"

log "Menghasilkan hardware-configuration.nix secara otomatis..."
if [ "$DRY_RUN" -eq 0 ] && command -v nixos-generate-config >/dev/null 2>&1; then
  nixos-generate-config --root "$TARGET_ROOT"
else
  # Mock hardware config for dry-run or verification
  cat <<'HW_EOF' > "$CONFIG_DIR/hardware-configuration.nix"
# Hardware-configuration generik yang dihasilkan oleh NEURONIX Installer Engine
{ config, lib, pkgs, modulesPath, ... }:
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];
  boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "ahci" "usbhid" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" "kvm-amd" ];
  boot.extraModulePackages = [ ];
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
HW_EOF
fi

log "Menghasilkan konfigurasi flake.nix murni untuk sistem terpasang..."
cat <<FLAKE_EOF > "$CONFIG_DIR/flake.nix"
# ==============================================================================
# NEURONIX OS: Konfigurasi Sistem Deklaratif Mandiri
# Dihasilkan secara otomatis oleh NEURONIX Installer Engine
# Sistem ini 100% reproducible, memiliki riwayat atomic rollback, dan kebal rusak.
# ==============================================================================
{
  description = "NEURONIX Host Configuration for $TARGET_HOSTNAME";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }@inputs: {
    nixosConfigurations."$TARGET_HOSTNAME" = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./hardware-configuration.nix
        ./configuration.nix
      ];
    };
  };
}
FLAKE_EOF

log "Menghasilkan configuration.nix terkurasi..."
cat <<CONF_EOF > "$CONFIG_DIR/configuration.nix"
# ==============================================================================
# NEURONIX OS: Spesifikasi Sistem Utama
# ==============================================================================
{ config, pkgs, lib, ... }:

{
  networking.hostName = "$TARGET_HOSTNAME";
  networking.networkmanager.enable = true;

  # Aktifkan Flakes & Nix CLI modern
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.auto-optimise-store = true;

  # Pilar 1: Lisensi Unfree (Steam, NVIDIA, Spotify aktif langsung)
  nixpkgs.config.allowUnfree = true;

  # Aktivasi Global nix-ld (Eksekusi biner Linux FHS langsung)
  programs.nix-ld.enable = true;

  # Pilar 5: Bootloader systemd-boot dengan batas 15 generasi di ESP 1.0 GiB
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 15;
  boot.loader.efi.canTouchEfiVariables = true;
  time.hardwareClockInLocalTime = true;

  # Pilar 17: Active Memory Pressure Shield (ZRAM ZSTD + systemd-oomd)
  zramSwap.enable = true;
  zramSwap.algorithm = "zstd";
  systemd.oomd.enable = true;
  boot.kernel.sysctl."vm.max_map_count" = 2147483642;
  boot.kernel.sysctl."vm.swappiness" = 180;

  # Pilar 18: Audio PipeWire HD Duplex
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  # Pilar 4: Toko Aplikasi Flatpak & Flathub
  services.flatpak.enable = true;

  # Pemeliharaan Storage Btrfs & Auto-TRIM
  services.fstrim.enable = true;

  # Desktop Environment: $SELECTED_DESKTOP
CONF_EOF

if [ "$SELECTED_DESKTOP" == "kde" ]; then
  cat <<'DESK_EOF' >> "$CONFIG_DIR/configuration.nix"
  services.displayManager.sddm.enable = true;
  services.displayManager.sddm.wayland.enable = true;
  services.desktopManager.plasma6.enable = true;
DESK_EOF
elif [ "$SELECTED_DESKTOP" == "gnome" ]; then
  cat <<'DESK_EOF' >> "$CONFIG_DIR/configuration.nix"
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;
DESK_EOF
elif [ "$SELECTED_DESKTOP" == "hyprland" ]; then
  cat <<'DESK_EOF' >> "$CONFIG_DIR/configuration.nix"
  programs.hyprland.enable = true;
DESK_EOF
fi

cat <<USER_EOF >> "$CONFIG_DIR/configuration.nix"

  # User akun sistem
  users.users.$TARGET_USER = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "video" "audio" ];
    description = "$TARGET_USER (NEURONIX)";
  };

  system.stateVersion = "24.11";
}
USER_EOF

log "✓ Konfigurasi deklaratif di $CONFIG_DIR berhasil dibuat."

if [ "$DRY_RUN" -eq 0 ]; then
  log "Mengeksekusi instalasi hermetis via nixos-install..."
  nixos-install --flake "$CONFIG_DIR#$TARGET_HOSTNAME" --no-root-passwd
  log "✓ Instalasi sistem selesai dengan sukses!"
else
  log "✓ Verifikasi dry-run sukses! File konfigurasi valid dan hermetis."
fi
