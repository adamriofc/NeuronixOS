{ lib, stdenv, rustc }:

let
  versionData = import ../../version.nix;
in
stdenv.mkDerivation rec {
  pname = "neuronix-daemon";
  version = versionData.version;

  src = ./.;

  nativeBuildInputs = [ rustc ];

  buildPhase = ''
    mkdir -p build
    rustc -O -C lto=thin -C opt-level=3 src/main.rs -o build/neuronix-daemon
  '';

  installPhase = ''
    mkdir -p $out/bin
    cp build/neuronix-daemon $out/bin/neuronix-daemon
    chmod +x $out/bin/neuronix-daemon
  '';

  meta = with lib; {
    description = "NEURONIX High-Performance Autonomous Systems Daemon & AST Engine";
    homepage = "https://github.com/adamriofc/NeuronixOS";
    license = licenses.asl20;
    platforms = platforms.linux;
  };
}
