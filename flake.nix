{
  description = "NEURONIX OS: Reproducible, Developer-First Linux Distribution Built on NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/3ed67ec0a4d3c7ab4ae1f04f8ee8df07bfa506a2";
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixos-generators, ... }@inputs:
    let
      versionData = import ./version.nix;
      supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      pkgsFor = system: import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      primarySystem = "x86_64-linux";
    in
    {
      inherit (versionData) version stateVersion;

      # Declarative Single Source of Truth Release Metadata
      releaseMeta = {
        inherit (versionData) version releaseTag stateVersion nixpkgsCommit primarySystem supportedSystems;
      };

      # Reusable declarative NEURONIX modules
      nixosModules = {
        platform = import ./modules/platform.nix;
        core = import ./modules/core;
        hardware = import ./modules/hardware/boot.nix;
        secureboot = import ./modules/hardware/secureboot.nix;
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
        opencode = import ./modules/services/opencode.nix;
        update = import ./modules/services/update.nix;
        kde = import ./modules/desktop/kde.nix;
        gnome = import ./modules/desktop/gnome.nix;
        hyprland = import ./modules/desktop/hyprland.nix;
        manual = import ./modules/core/manual.nix;
        sentinel = import ./modules/core/sentinel.nix;
        tuning = import ./modules/hardware/tuning.nix;
        mesh = import ./modules/services/mesh.nix;
        daemon = import ./modules/services/daemon.nix;
        conductor = import ./modules/services/conductor.nix;
        ebpfLsm = import ./modules/security/ebpf-lsm.nix;
        lanzaboote = import ./modules/security/lanzaboote.nix;
      };

      # Target installed system configuration (Default Desktop x86_64)
      nixosConfigurations."neuronix-desktop" = nixpkgs.lib.nixosSystem {
        system = primarySystem;
        specialArgs = { inherit self; };
        modules = [
          ./modules/platform.nix
          ./modules/desktop/gnome.nix
          ./hosts/desktop
        ];
      };

      # Target installed system configuration (ARM64 / aarch64 Desktop)
      nixosConfigurations."neuronix-desktop-aarch64" = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        specialArgs = { inherit self; };
        modules = [
          ./modules/platform.nix
          ./modules/desktop/gnome.nix
          ./hosts/desktop
        ];
      };

      # Konfigurasi Live ISO Installer Mandiri
      nixosConfigurations."neuronix-iso" = nixpkgs.lib.nixosSystem {
        system = primarySystem;
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

      # Paket kustom NEURONIX (Multi-Architecture: x86_64-linux & aarch64-linux)
      packages = forAllSystems (system:
        let
          pkgs = pkgsFor system;
        in
        {
          neuronix-core = pkgs.python3.pkgs.callPackage ./packages/neuronix-core { };
          neuronix-center = pkgs.callPackage ./packages/neuronix-center { };
          neuronix-cli = pkgs.callPackage ./packages/neuronix-cli { };
          neuronix-daemon = pkgs.callPackage ./packages/neuronix-daemon { };
          opencode = pkgs.callPackage ./packages/opencode { };
          conductor = pkgs.callPackage ./packages/conductor { };
          conductor-runtime = pkgs.python3.pkgs.callPackage ./packages/conductor-runtime {
            neuronix-core = pkgs.python3.pkgs.callPackage ./packages/neuronix-core { };
          };
          conductor-mcp = pkgs.python3.pkgs.callPackage ./packages/conductor-mcp {
            neuronix-core = pkgs.python3.pkgs.callPackage ./packages/neuronix-core { };
            conductor-runtime = pkgs.python3.pkgs.callPackage ./packages/conductor-runtime {
              neuronix-core = pkgs.python3.pkgs.callPackage ./packages/neuronix-core { };
            };
          };
        } // (nixpkgs.lib.optionalAttrs (system == primarySystem) {
          iso = self.nixosConfigurations."neuronix-iso".config.system.build.isoImage;
        })
      );

      # Development Shell hermetis (Multi-Architecture)
      devShells = forAllSystems (system:
        let
          pkgs = pkgsFor system;
        in
        {
          default = pkgs.mkShell {
            name = "neuronix-dev-shell";
            buildInputs = [
              pkgs.nix-diff
              nixos-generators.packages.${system}.default
              pkgs.qemu
              pkgs.calamares
              pkgs.btrfs-progs
            ];
            shellHook = ''
              echo "========================================================"
              echo "  NEURONIX OS Distribution Engineering Substrate       "
              echo "  Ready for building ISO, modules, & test verification  "
              echo "========================================================"
            '';
          };
        }
      );
    };
}
