{ pkgs, lib, ... }:

{
  # Jaringan Utama via NetworkManager
  networking.networkmanager = {
    enable = true;
    # Pilar 21: Deteksi Otomatis Captive Portal Wi-Fi Publik (Hotel/Cafe/Bandara)
    settings = {
      connectivity = {
        uri = "http://nmcheck.gnome.org/check_network_status";
        interval = 300;
      };
    };
  };

  # Pilar 16: Skrip Pembantu Impor Root CA Korporat / Kampus (Zscaler/Fortinet Proxy)
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
      echo "Mendaftarkan sertifikat $CERT_NAME ke trust-store sistem..."
      sudo cp "$CERT_PATH" "/etc/ssl/certs/$CERT_NAME"
      echo "Memperbarui direktori sertifikat..."
      sudo update-ca-certificates 2>/dev/null || true
      echo "✓ Sertifikat $CERT_NAME berhasil didaftarkan ke trust-store OS & Nix daemon."
    '')
  ];
}
