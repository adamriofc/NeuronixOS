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
        echo "Usage: neuronix-add-ca <path-to-certificate.crt/.pem>"
        exit 1
      fi
      CERT_PATH="$1"
      if [ ! -f "$CERT_PATH" ]; then
        echo "Error: Certificate file not found at $CERT_PATH" >&2
        exit 1
      fi

      # Validate PEM format
      if ! grep -q "BEGIN CERTIFICATE" "$CERT_PATH" || ! grep -q "END CERTIFICATE" "$CERT_PATH"; then
        echo "Error: File does not contain valid PEM certificate delimiters." >&2
        exit 1
      fi

      CERT_HASH=$(sha256sum "$CERT_PATH" | awk '{print $1}')
      CA_DIR="/var/lib/neuronix/ca"
      TARGET_CA_FILE="$CA_DIR/neuronix-ca-$CERT_HASH.crt"
      SYSTEM_SSL_FILE="/etc/ssl/certs/neuronix-ca-$CERT_HASH.crt"

      echo "Enrolling certificate (SHA-256: ''${CERT_HASH:0:16}...) into trust store..."
      sudo mkdir -p "$CA_DIR"
      sudo cp "$CERT_PATH" "$TARGET_CA_FILE"
      sudo chmod 644 "$TARGET_CA_FILE"

      if [ -d "/etc/ssl/certs" ]; then
        sudo cp "$TARGET_CA_FILE" "$SYSTEM_SSL_FILE"
        if command -v update-ca-certificates >/dev/null 2>&1; then
          sudo update-ca-certificates
        fi
      fi

      # Verify Postcondition
      if [ -d "/etc/ssl/certs" ] && [ ! -f "$SYSTEM_SSL_FILE" ]; then
        echo "Error: Postcondition verification failed: $SYSTEM_SSL_FILE not found." >&2
        exit 1
      fi

      echo "✓ Certificate enrolled successfully with content-addressed ID: neuronix-ca-$CERT_HASH"
    '')
  ];
}
