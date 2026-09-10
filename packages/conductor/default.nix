{ lib, rustPlatform }:

rustPlatform.buildRustPackage rec {
  pname = "conductor";
  version = (import ../../version.nix).version;

  src = ./.;

  cargoLock = {
    lockFile = ./Cargo.lock;
  };

  meta = with lib; {
    description = "NEURONIX Conductor Native Minimalist Operating Surface & Terminal Subsystem";
    homepage = "https://github.com/adamriofc/NeuronixOS";
    license = licenses.asl20;
    platforms = platforms.linux;
  };
}
