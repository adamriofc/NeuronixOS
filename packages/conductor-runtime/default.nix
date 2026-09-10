{ lib, buildPythonPackage, setuptools, neuronix-core }:

let
  versionData = import ../../version.nix;
in
buildPythonPackage {
  pname = "conductor-runtime";
  version = versionData.version;
  pyproject = true;

  src = ./.;

  build-system = [
    setuptools
  ];

  dependencies = [
    neuronix-core
  ];

  propagatedBuildInputs = [
    neuronix-core
  ];

  pythonImportsCheck = [
    "conductor_runtime"
  ];

  meta = with lib; {
    description = "NEURONIX Conductor Zero-Idle Capability Runtime & Control Broker";
    homepage = "https://github.com/adamriofc/NeuronixOS";
    license = licenses.asl20;
    maintainers = [ ];
    platforms = platforms.linux;
  };
}

