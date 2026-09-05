{ lib, stdenv, makeWrapper, bash, coreutils, nix, jq }:

let
  versionData = import ../../version.nix;
in
stdenv.mkDerivation rec {
  pname = "neuronix-cli";
  version = versionData.version;

  src = ../../src;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    mkdir -p $out/bin $out/share/neuronix
    cp neuronix $out/bin/neuronix
    cp mcp_server.sh $out/share/neuronix/mcp_server.sh
    cp shadow_vm.sh $out/share/neuronix/shadow_vm.sh
    chmod +x $out/bin/neuronix $out/share/neuronix/*.sh

    wrapProgram $out/bin/neuronix \
      --prefix PATH : ${lib.makeBinPath [ bash coreutils nix jq ]}
  '';

  meta = with lib; {
    description = "NEURONIX Developer & System Substrate CLI Engine";
    homepage = "https://github.com/adamriofc/NeuronixOS";
    license = licenses.asl20;
    platforms = platforms.linux;
  };
}
