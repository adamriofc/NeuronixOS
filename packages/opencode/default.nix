{ lib
, stdenv
, fetchurl
, autoPatchelfHook
, makeWrapper
, makeDesktopItem
, copyDesktopItems
, zlib
, ripgrep
}:

let
  version = "1.18.29";

  sources = {
    x86_64-linux = {
      url = "https://github.com/anomalyco/opencode/releases/download/v${version}/opencode-linux-x64.tar.gz";
      sha256 = "ea800b7ff56226b70952126c9fc1e2517ca4c4b5682fd9d3f9e87449697a1194";
    };
    aarch64-linux = {
      url = "https://github.com/anomalyco/opencode/releases/download/v${version}/opencode-linux-arm64.tar.gz";
      sha256 = "70baf769395ca4e7a68924026530c390eace194f3b7e4919d4efcb2aa2eed3c0";
    };
  };

  system = stdenv.hostPlatform.system;
  source = sources.${system} or (throw "Unsupported platform for opencode: ${system}");
in
stdenv.mkDerivation rec {
  pname = "opencode";
  inherit version;

  src = fetchurl {
    inherit (source) url sha256;
  };

  sourceRoot = ".";

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
    copyDesktopItems
  ];

  buildInputs = [
    stdenv.cc.cc.lib
    zlib
  ];

  desktopItems = [
    (makeDesktopItem {
      name = "opencode";
      exec = "opencode";
      icon = "utilities-terminal";
      desktopName = "OpenCode AI Agent";
      genericName = "AI Coding Agent";
      comment = "The open source AI coding agent built for the terminal";
      categories = [ "Development" "System" "Utility" ];
      terminal = true;
    })
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    install -Dm755 opencode $out/bin/opencode

    wrapProgram $out/bin/opencode \
      --prefix PATH : ${lib.makeBinPath [ ripgrep ]}

    runHook postInstall
  '';

  meta = with lib; {
    description = "The open source AI coding agent built for the terminal";
    homepage = "https://opencode.ai";
    license = licenses.mit;
    platforms = [ "x86_64-linux" "aarch64-linux" ];
    mainProgram = "opencode";
  };
}
