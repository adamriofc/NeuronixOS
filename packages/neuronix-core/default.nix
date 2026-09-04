{ lib, python3Packages }:

python3Packages.buildPythonPackage {
  pname = "neuronix-core";
  version = "1.0.3";

  src = ./.;

  propagatedBuildInputs = [ ];

  meta = with lib; {
    description = "Canonical shared domain logic for NEURONIX OS";
    homepage = "https://github.com/adamriofc/neuronix";
    license = licenses.asl20;
    maintainers = [ ];
  };
}
