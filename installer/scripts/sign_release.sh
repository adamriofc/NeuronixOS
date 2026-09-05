#!/usr/bin/env bash
# ==============================================================================
# NEURONIX OS Cryptographic Release Signing & Signature Verification Tool
# Standard: Ed25519 Checksum Signature Verification against Trusted Root Anchor
# Root Key Anchor: docs/security/RELEASE_SIGNING_KEY.pub
#
# Copyright (c) 2026 NEURONIX Contributors
# Licensed under the Apache License, Version 2.0
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DIST_DIR="${PROJECT_ROOT}/dist"
CHECKSUM_FILE="${DIST_DIR}/SHA256SUMS"
SIG_FILE="${DIST_DIR}/SHA256SUMS.sig"
KEY_DIR="${NEURONIX_KEY_DIR:-${PROJECT_ROOT}/.keys}"
TRUSTED_PUB_KEY="${PROJECT_ROOT}/docs/security/RELEASE_SIGNING_KEY.pub"

action="${1:-verify}"

case "$action" in
    sign)
        if [[ ! -f "$CHECKSUM_FILE" ]]; then
            echo "[ERROR] Checksum database $CHECKSUM_FILE not found." >&2
            exit 1
        fi

        mkdir -p "$DIST_DIR"
        mkdir -p "$KEY_DIR"

        PRIV_KEY="${KEY_DIR}/release_sign.key"

        if [[ -n "${NEURONIX_SIGNING_KEY:-}" ]]; then
            if [[ -f "${NEURONIX_SIGNING_KEY}" ]]; then
                PRIV_KEY="${NEURONIX_SIGNING_KEY}"
            else
                PRIV_KEY="${KEY_DIR}/env_signing.key"
                echo "${NEURONIX_SIGNING_KEY}" > "$PRIV_KEY"
                chmod 600 "$PRIV_KEY"
            fi
        elif [[ ! -f "$PRIV_KEY" ]]; then
            echo "[ERROR] Release signing key not found at $PRIV_KEY." >&2
            echo "[ERROR] Provide NEURONIX_SIGNING_KEY secret or provision key at $PRIV_KEY." >&2
            exit 1
        fi

        openssl pkeyutl -sign -inkey "$PRIV_KEY" -in "$CHECKSUM_FILE" -rawin -out "$SIG_FILE"
        echo "[SIGN] Generated cryptographic Ed25519 signature at $SIG_FILE"

        if [[ -f "$TRUSTED_PUB_KEY" ]]; then
            cp "$TRUSTED_PUB_KEY" "${DIST_DIR}/release_sign.pub"
        else
            openssl pkey -in "$PRIV_KEY" -pubout -out "${DIST_DIR}/release_sign.pub" 2>/dev/null
        fi

        # Immediate verification
        echo "[SIGN] Verifying generated signature against trust anchor..."
        openssl pkeyutl -verify -pubin -inkey "${DIST_DIR}/release_sign.pub" -sigfile "$SIG_FILE" -in "$CHECKSUM_FILE" -rawin
        echo "[SIGN] Verification succeeded."
        ;;

    verify)
        if [[ ! -f "$CHECKSUM_FILE" ]]; then
            echo "[ERROR] Checksum database $CHECKSUM_FILE not found." >&2
            exit 1
        fi

        if [[ ! -f "$SIG_FILE" ]]; then
            echo "[ERROR] Signature file $SIG_FILE not found." >&2
            echo "[ERROR] Refusing to synthesize ad-hoc keys in verification mode." >&2
            exit 1
        fi

        # Prioritize root trust anchor in repository
        PUB_KEY="$TRUSTED_PUB_KEY"
        if [[ ! -f "$PUB_KEY" ]]; then
            PUB_KEY="${DIST_DIR}/release_sign.pub"
        fi

        if [[ ! -f "$PUB_KEY" ]]; then
            echo "[ERROR] Trusted public key anchor not found at $PUB_KEY" >&2
            exit 1
        fi

        # Verify key fingerprint against canonical trust anchor
        FINGERPRINT_FILE="${PROJECT_ROOT}/docs/security/RELEASE_SIGNING_KEY.fingerprint"
        if [[ -f "$FINGERPRINT_FILE" && -f "$PUB_KEY" ]]; then
            EXPECTED_FP=$(tr -d ' \n\r' < "$FINGERPRINT_FILE")
            ACTUAL_FP=$(sha256sum "$PUB_KEY" | awk '{print $1}')
            if [[ "$ACTUAL_FP" != "$EXPECTED_FP" ]]; then
                echo "[ERROR] Public key fingerprint mismatch! Expected: $EXPECTED_FP, Got: $ACTUAL_FP" >&2
                exit 1
            fi
            echo "[VERIFY] Trust anchor fingerprint verified: $ACTUAL_FP"
        fi

        if openssl pkeyutl -verify -pubin -inkey "$PUB_KEY" -sigfile "$SIG_FILE" -in "$CHECKSUM_FILE" -rawin 2>/dev/null; then
            echo "[VERIFY] Cryptographic signature $SIG_FILE verified against trusted root $PUB_KEY: VALID"
        else
            echo "[ERROR] Signature verification FAILED against $PUB_KEY." >&2
            exit 1
        fi
        ;;

    *)
        echo "Usage: $0 [sign|verify]"
        exit 1
        ;;
esac
