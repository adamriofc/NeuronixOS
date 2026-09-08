{ lib, buildPythonPackage, setuptools, pyyaml }:

let
  versionData = import ../../version.nix;
in
buildPythonPackage {
  pname = "neuronix-core";
  version = versionData.version;
  pyproject = true;

  src = ./.;

  build-system = [
    setuptools
  ];

  dependencies = [
    pyyaml
  ];

  propagatedBuildInputs = [
    pyyaml
  ];

  pythonImportsCheck = [
    "neuronix_core"
  ];

  meta = with lib; {
    description = "Canonical shared domain logic library for NEURONIX OS";
    homepage = "https://github.com/adamriofc/NeuronixOS";
    license = licenses.asl20;
    maintainers = [ ];
    platforms = platforms.linux;
  };
}
