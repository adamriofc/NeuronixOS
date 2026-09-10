{ lib, python3Packages, neuronix-core }:

python3Packages.buildPythonPackage rec {
  pname = "conductor-runtime";
  version = (import ../../version.nix).version;

  src = ./.;

  propagatedBuildInputs = [
    neuronix-core
  ];

  doCheck = false;

  meta = with lib; {
    description = "NEURONIX Conductor Zero-Idle Capability Runtime & Control Broker";
    homepage = "https://github.com/adamriofc/NeuronixOS";
    license = licenses.asl20;
    platforms = platforms.linux;
  };
}
