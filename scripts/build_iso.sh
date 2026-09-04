#!/usr/bin/env bash
# ==============================================================================
# NEURONIX OS: Official Live ISO Build & Artifact Generation Utility
# ==============================================================================
# Builds a bootable Calamares-integrated live installation ISO image directly
# from the declarative Flake definition, computes SHA-256 integrity checksums,
# and outputs standard release metadata.
# ==============================================================================
set -euo pipefail

BOLD="\033[1m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
CYAN="\033[1;36m"
GRAY="\033[0;90m"
RESET="\033[0m"

log_info()    { echo -e "${CYAN}[NEURONIX-ISO]${RESET} $*"; }
log_success() { echo -e "${GREEN}[NEURONIX-ISO ✓]${RESET} $*"; }
log_warn()    { echo -e "${YELLOW}[NEURONIX-ISO ⚠]${RESET} $*"; }
log_error()   { echo -e "${RED}[NEURONIX-ISO ✗]${RESET} $*" >&2; }

# Locate repository root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

echo -e "\n${BOLD}======================================================================${RESET}"
echo -e "       ${CYAN}NEURONIX OS: OFFICIAL LIVE INSTALLER COMPILATION UTILITY${RESET}"
echo -e "${BOLD}======================================================================${RESET}\n"

# Verify Nix & Flakes prerequisite
if ! command -v nix >/dev/null 2>&1; then
    log_error "Nix package manager is not installed or not in PATH."
    exit 1
fi

# Detect architecture
HOST_ARCH="$(uname -m)"
case "$HOST_ARCH" in
    x86_64) NIX_ARCH="x86_64-linux" ;;
    aarch64|arm64) NIX_ARCH="aarch64-linux" ;;
    *) NIX_ARCH="x86_64-linux" ;;
esac

TARGET_ARCH="${1:-$NIX_ARCH}"
log_info "Target System Architecture : ${BOLD}${TARGET_ARCH}${RESET}"

# Verify disk space
STORE_AVAIL_KB=$(df -k /nix 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")
STORE_AVAIL_GB=$((STORE_AVAIL_KB / 1024 / 1024))
log_info "Available Space on /nix     : ${STORE_AVAIL_GB} GiB"
if [[ $STORE_AVAIL_GB -lt 6 ]]; then
    log_warn "Low disk space detected (< 6 GiB). Live ISO compilation may exhaust disk space."
fi

# Read canonical version
VERSION="1.0.3"
if [[ -f "${REPO_ROOT}/version.nix" ]]; then
    VERSION=$(grep -E 'version\s*=' "${REPO_ROOT}/version.nix" | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/' || echo "1.0.3")
fi
log_info "Canonical Release Version  : ${BOLD}v${VERSION}${RESET}"

OUT_DIR="${REPO_ROOT}/dist"
mkdir -p "${OUT_DIR}"

log_info "Initiating pure Flake evaluation and derivation build..."
log_info "Command: nix build .#packages.${TARGET_ARCH}.iso --out-link result-iso"

BUILD_START=$(date +%s)
nix build ".#packages.${TARGET_ARCH}.iso" --out-link "${REPO_ROOT}/result-iso" --extra-experimental-features "nix-command flakes"
BUILD_END=$(date +%s)
DURATION=$((BUILD_END - BUILD_START))

if [[ ! -d "${REPO_ROOT}/result-iso" ]]; then
    log_error "Build output 'result-iso' directory not found."
    exit 1
fi

# Find compiled ISO image
ISO_PATH=$(find "${REPO_ROOT}/result-iso/iso" -maxdepth 1 -name "*.iso" | head -n 1 || true)
if [[ -z "${ISO_PATH}" || ! -f "${ISO_PATH}" ]]; then
    log_error "No .iso file found inside result-iso/iso."
    exit 1
fi

FINAL_ISO_NAME="neuronix-os-${VERSION}-${HOST_ARCH}.iso"
FINAL_ISO_PATH="${OUT_DIR}/${FINAL_ISO_NAME}"

log_info "Staging ISO artifact to: ${FINAL_ISO_PATH}..."
cp -f "${ISO_PATH}" "${FINAL_ISO_PATH}"
chmod 644 "${FINAL_ISO_PATH}"

# Generate SHA-256 Checksum
log_info "Computing SHA-256 cryptographic checksum..."
CHECKSUM=$(sha256sum "${FINAL_ISO_PATH}" | awk '{print $1}')
echo "${CHECKSUM}  ${FINAL_ISO_NAME}" > "${OUT_DIR}/SHA256SUMS"

ISO_SIZE=$(du -h "${FINAL_ISO_PATH}" | awk '{print $1}')

echo -e "\n${BOLD}======================================================================${RESET}"
echo -e "                   ${GREEN}COMPILATION SUCCESSFUL (100%)${RESET}"
echo -e "${BOLD}======================================================================${RESET}"
echo -e "  Artifact Name    : ${BOLD}${FINAL_ISO_NAME}${RESET}"
echo -e "  Artifact Size    : ${BOLD}${ISO_SIZE}${RESET}"
echo -e "  Target Location  : ${CYAN}${FINAL_ISO_PATH}${RESET}"
echo -e "  SHA-256 Checksum : ${YELLOW}${CHECKSUM}${RESET}"
echo -e "  Checksum File    : ${CYAN}${OUT_DIR}/SHA256SUMS${RESET}"
echo -e "  Build Duration   : ${DURATION} seconds"
echo -e "${BOLD}======================================================================${RESET}\n"

log_success "Bootable Live ISO is ready for deployment and distribution."
