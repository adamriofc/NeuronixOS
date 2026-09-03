{ lib, python3, makeDesktopItem, copyDesktopItems }:

let
  versionData = import ../../version.nix;
in
python3.pkgs.buildPythonApplication rec {
  pname = "neuronix-center";
  version = versionData.version;
  format = "other";

  src = ./.;

  nativeBuildInputs = [ copyDesktopItems ];
  propagatedBuildInputs = with python3.pkgs; [
    tkinter
  ];

  installPhase = ''
    mkdir -p $out/bin
    cp neuronix_center.py $out/bin/neuronix-center
    chmod +x $out/bin/neuronix-center
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "neuronix-center";
      exec = "neuronix-center";
      icon = "preferences-system";
      desktopName = "NEURONIX Control Center";
      genericName = "System Control Center";
      comment = "Control center, system telemetry, and time-travel rollback for NEURONIX OS";
      categories = [ "System" "Settings" ];
    })
  ];

  meta = with lib; {
    description = "NEURONIX Control Center & Time-Travel Guard";
    homepage = "https://github.com/adamriofc/neuronix";
    license = licenses.asl20;
    platforms = platforms.linux;
  };
}
