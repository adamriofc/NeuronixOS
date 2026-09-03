{ lib, stdenv, makeWrapper, makeDesktopItem, copyDesktopItems, bash, coreutils, jq }:

let
  versionData = import ../../version.nix;
in
stdenv.mkDerivation rec {
  pname = "opencode";
  version = versionData.version;

  src = ./.;

  nativeBuildInputs = [ makeWrapper copyDesktopItems ];

  desktopItems = [
    (makeDesktopItem {
      name = "opencode";
      exec = "opencode interactive";
      icon = "utilities-terminal";
      desktopName = "OpenCode AI Agent";
      genericName = "AI System Copilot";
      comment = "Autonomous declarative AI coding and system copilot for NEURONIX OS";
      categories = [ "Development" "System" "Utility" ];
      terminal = true;
    })
  ];

  installPhase = ''
    mkdir -p $out/bin $out/share/applications
    cp opencode-launcher.sh $out/bin/opencode
    chmod +x $out/bin/opencode

    wrapProgram $out/bin/opencode \
      --prefix PATH : ${lib.makeBinPath [ bash coreutils jq ]}
  '';

  meta = with lib; {
    description = "Autonomous Declarative AI Coding and System Copilot for NEURONIX OS";
    homepage = "https://github.com/adamriofc/neuronix";
    license = licenses.asl20;
    platforms = platforms.linux;
  };
}
