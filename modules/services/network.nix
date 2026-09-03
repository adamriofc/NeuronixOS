{ pkgs, lib, ... }:

{
  # Jaringan Utama via NetworkManager
  networking.networkmanager = {
    enable = true;
    # Captive portal detection for public Wi-Fi networks
    settings = {
      connectivity = {
        uri = "http://nmcheck.gnome.org/check_network_status";
        interval = 300;
      };
    };
  };

  # Enterprise / Institutional Root CA import utility
  environment.systemPackages = with pkgs; [
    networkmanager
    networkmanager-openvpn
    (writeShellScriptBin "neuronix-add-ca" ''
      set -euo pipefail
      if [ "$#" -ne 1 ]; then
        echo "Penggunaan: neuronix-add-ca <path-ke-sertifikat.crt/.pem>"
        exit 1
      fi
      CERT_PATH="$1"
      if [ ! -f "$CERT_PATH" ]; then
        echo "Error: File sertifikat tidak ditemukan di $CERT_PATH"
        exit 1
      fi
      CERT_NAME=$(basename "$CERT_PATH")
      echo "Enrolling certificate $CERT_NAME into system trust store..."
      sudo cp "$CERT_PATH" "/etc/ssl/certs/$CERT_NAME"
      echo "Memperbarui direktori sertifikat..."
      sudo update-ca-certificates 2>/dev/null || true
      echo "✓ Certificate $CERT_NAME enrolled successfully into OS & Nix daemon trust store."
    '')
  ];
}
