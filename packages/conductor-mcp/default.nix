{ lib, buildPythonPackage, setuptools, neuronix-core, conductor-runtime }:

let
  versionData = import ../../version.nix;
in
buildPythonPackage {
  pname = "conductor-mcp";
  version = versionData.version;
  pyproject = true;

  src = ./.;

  build-system = [
    setuptools
  ];

  dependencies = [
    neuronix-core
    conductor-runtime
  ];

  propagatedBuildInputs = [
    neuronix-core
    conductor-runtime
  ];

  pythonImportsCheck = [
    "conductor_mcp"
  ];

  meta = with lib; {
    description = "NEURONIX Conductor MCP 2026-07-28 Universal Agent Adapter";
    homepage = "https://github.com/adamriofc/NeuronixOS";
    license = licenses.asl20;
    maintainers = [ ];
    platforms = platforms.linux;
  };
}

