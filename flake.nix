{
  description = "NEURONIX OS: Reproducible, Developer-First Linux Distribution Built on NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixos-generators, ... }@inputs:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
    in
    {
      # Modul deklaratif NEURONIX yang dapat digunakan kembali
      nixosModules = {
        core = import ./modules/core;
        hardware = import ./modules/hardware/boot.nix;
        firmware = import ./modules/hardware/firmware.nix;
        audio = import ./modules/hardware/audio.nix;
        power = import ./modules/hardware/power.nix;
        nvidia = import ./modules/hardware/nvidia-prime.nix;
        cpu = import ./modules/hardware/cpu.nix;
        memoryShield = import ./modules/services/memory-shield.nix;
        storage = import ./modules/services/storage.nix;
        flatpak = import ./modules/services/flatpak.nix;
        network = import ./modules/services/network.nix;
        desktopTweaks = import ./modules/services/desktop-tweaks.nix;
        printing = import ./modules/services/printing.nix;
        security = import ./modules/services/security.nix;
        kde = import ./modules/desktop/kde.nix;
        gnome = import ./modules/desktop/gnome.nix;
        hyprland = import ./modules/desktop/hyprland.nix;
      };

      # Konfigurasi sistem target terpasang (Default Desktop)
      nixosConfigurations."neuronix-desktop" = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          ./modules/core
          ./modules/hardware/boot.nix
          ./modules/hardware/firmware.nix
          ./modules/hardware/audio.nix
          ./modules/hardware/power.nix
          ./modules/hardware/cpu.nix
          ./modules/services/memory-shield.nix
          ./modules/services/storage.nix
          ./modules/services/flatpak.nix
          ./modules/services/network.nix
          ./modules/services/desktop-tweaks.nix
          ./modules/services/printing.nix
          ./modules/services/security.nix
          ./modules/desktop/kde.nix
          ./hosts/desktop
        ];
      };

      # Konfigurasi Live ISO Installer Mandiri
      nixosConfigurations."neuronix-iso" = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-graphical-calamares.nix"
          ./modules/core
          ./modules/hardware/firmware.nix
          ./modules/hardware/audio.nix
          ./modules/services/memory-shield.nix
          ./modules/services/storage.nix
          ./modules/services/network.nix
          ./hosts/iso
        ];
      };

      # Paket kustom NEURONIX
      packages.${system} = {
        neuronix-center = pkgs.callPackage ./packages/neuronix-center { };
        neuronix-cli = pkgs.callPackage ./packages/neuronix-cli { };
        iso = self.nixosConfigurations."neuronix-iso".config.system.build.isoImage;
      };

      # Development Shell hermetis
      devShells.${system}.default = pkgs.mkShell {
        name = "neuronix-dev-shell";
        buildInputs = with pkgs; [
          nix-diff
          nixos-generators
          qemu
          calamares
          btrfs-progs
        ];
        shellHook = ''
          echo "========================================================"
          echo "  NEURONIX OS Distribution Engineering Substrate       "
          echo "  Ready for building ISO, modules, & test verification  "
          echo "========================================================"
        '';
      };
    };
}
