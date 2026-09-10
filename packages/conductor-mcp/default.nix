{ lib, python3Packages, neuronix-core, conductor-runtime }:

python3Packages.buildPythonPackage rec {
  pname = "conductor-mcp";
  version = (import ../../version.nix).version;

  src = ./.;

  propagatedBuildInputs = [
    neuronix-core
    conductor-runtime
  ];

  doCheck = false;

  meta = with lib; {
    description = "NEURONIX Conductor MCP 2026-07-28 Universal Agent Adapter";
    homepage = "https://github.com/adamriofc/NeuronixOS";
    license = licenses.asl20;
    platforms = platforms.linux;
  };
}
