{
  description = "NEURONIX: The Deterministic, Self-Healing Workstation & Ephemeral Sandbox Substrate";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      rec {
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "neuronix";
          version = "0.1.0-alpha";

          src = ./.;

          nativeBuildInputs = [ pkgs.makeWrapper ];

          installPhase = ''
            mkdir -p $out/bin
            cp src/neuronix $out/bin/neuronix
            chmod +x $out/bin/neuronix

            wrapProgram $out/bin/neuronix \
              --prefix PATH : ${pkgs.lib.makeBinPath [
                pkgs.bash
                pkgs.coreutils
                pkgs.gawk
                pkgs.findutils
                pkgs.systemd
                pkgs.util-linux
                pkgs.nix
              ]}
          '';

          meta = with pkgs.lib; {
            description = "Deterministic, Self-Healing AI-Augmented OS Substrate";
            homepage = "https://github.com/adamrofc/neuronix";
            license = licenses.asl20;
            maintainers = [ "adamrofc" ];
            mainProgram = "neuronix";
            platforms = platforms.linux ++ platforms.darwin;
          };
        };

        apps.default = flake-utils.lib.mkApp {
          drv = packages.default;
        };

        devShells.default = pkgs.mkShell {
          buildInputs = [
            packages.default
            pkgs.shellcheck
            pkgs.git
          ];
          shellHook = ''
            echo "🚀 NEURONIX DevShell Active (v0.1.0-alpha)"
            echo "Type 'neuronix help' to inspect commands."
          '';
        };
      }
    );
}
