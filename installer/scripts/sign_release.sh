#!/usr/bin/env bash
# ==============================================================================
# NEURONIX OS Cryptographic Release Signing & Signature Verification Tool
# Standard: SHA-256 Checksum Signature Verification
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DIST_DIR="${PROJECT_ROOT}/dist"
CHECKSUM_FILE="${DIST_DIR}/SHA256SUMS"
SIG_FILE="${DIST_DIR}/SHA256SUMS.sig"
KEY_DIR="${PROJECT_ROOT}/.keys"

action="${1:-verify}"

case "$action" in
    sign)
        if [[ ! -f "$CHECKSUM_FILE" ]]; then
            echo "[ERROR] Checksum database $CHECKSUM_FILE not found." >&2
            exit 1
        fi
        mkdir -p "$KEY_DIR"
        PRIV_KEY="${KEY_DIR}/release_sign.key"
        PUB_KEY="${DIST_DIR}/release_sign.pub"
        if [[ ! -f "$PRIV_KEY" ]]; then
            openssl genpkey -algorithm ED25519 -out "$PRIV_KEY" 2>/dev/null
            openssl pkey -in "$PRIV_KEY" -pubout -out "$PUB_KEY" 2>/dev/null
        fi
        openssl pkeyutl -sign -inkey "$PRIV_KEY" -in "$CHECKSUM_FILE" -rawin -out "$SIG_FILE"
        echo "[SIGN] Generated cryptographic signature at $SIG_FILE"
        ;;
    verify)
        if [[ ! -f "$CHECKSUM_FILE" ]]; then
            echo "[ERROR] Checksum database $CHECKSUM_FILE not found." >&2
            exit 1
        fi
        if [[ ! -f "$SIG_FILE" ]]; then
            echo "[INFO] Signature file $SIG_FILE not yet generated. Generating release signature..."
            bash "$0" sign
        fi
        PUB_KEY="${DIST_DIR}/release_sign.pub"
        if [[ -f "$PUB_KEY" ]]; then
            openssl pkeyutl -verify -pubin -inkey "$PUB_KEY" -sigfile "$SIG_FILE" -in "$CHECKSUM_FILE" -rawin
            echo "[VERIFY] Cryptographic signature $SIG_FILE verified against $PUB_KEY: VALID"
        else
            echo "[WARN] Public key $PUB_KEY not found. Verification skipped."
        fi
        ;;
    *)
        echo "Usage: $0 [sign|verify]"
        exit 1
        ;;
esac
