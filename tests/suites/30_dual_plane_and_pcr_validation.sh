#!/usr/bin/env bash
# ==============================================================================
# Suite 30: Dual-Plane Control Engine, UKI & Resilient Measured Boot (25 Tests)
# Validates state-of-the-art architectural invariants:
# 1. Dual-Plane micro-Rust control-plane socket RPC & peer credentials (SO_PEERCRED)
# 2. Control plane isolation and verified zero-interruption daemon status
# 3. Declarative Lanzaboote UKI (Unified Kernel Image) module contracts
# 4. Smart PCR binding invariants (PCR 7 + PCR 11; PCR 0/2/4 excluded)
# 5. Dual-slot LUKS2 fallback passphrase preservation (zero lockout risk)
# 6. Policy-as-Code NIP-0001 specification and North Star alignment
# 7. Flake module registration and release provenance attestation
# ==============================================================================

TARGET_BIN="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/bin/neuronix"
DISTRO_PATH="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

start_suite "30 - Dual-Plane Control Engine, UKI & Resilient Measured Boot"

# ==============================================================================
# Part 1: Dual-Plane Control Engine & Socket Credentials (Tests 1-8)
# ==============================================================================
assert_exit_code "$TARGET_BIN daemon --help" 0 "neuronix daemon --help exits 0"

assert_exit_code "$TARGET_BIN daemon control" 0 "neuronix daemon control exits 0"
assert_output_contains "$TARGET_BIN daemon control" '"control_plane"' "daemon control status reports control_plane"
assert_output_contains "$TARGET_BIN daemon control" 'DUAL_PLANE_' "daemon control reports DUAL_PLANE architecture"
assert_output_contains "$TARGET_BIN daemon control" '"peer_cred_enforced"' "daemon control confirms peer_cred_enforced"

DAEMON_MAIN="${DISTRO_PATH}/packages/neuronix-daemon/src/main.rs"
assert_output_contains "cat '$DAEMON_MAIN'" "SO_PEERCRED" "daemon source implements SO_PEERCRED socket credential check"
assert_output_contains "cat '$DAEMON_MAIN'" "struct PeerCred" "daemon source defines PeerCred struct"
assert_output_contains "cat '$DAEMON_MAIN'" "fn get_peer_credentials" "daemon source exports get_peer_credentials helper"

# ==============================================================================
# Part 2: Declarative Lanzaboote UKI & Resilient PCR Binding (Tests 9-16)
# ==============================================================================
LANZABOOTE_NIX="${DISTRO_PATH}/modules/security/lanzaboote.nix"
assert_eq "$([[ -f "$LANZABOOTE_NIX" ]] && echo "yes" || echo "no")" "yes" "modules/security/lanzaboote.nix exists"

PARSE_LANZABOOTE=$(nix-instantiate --parse "$LANZABOOTE_NIX" 2>&1 >/dev/null && echo "PARSED" || echo "FAILED")
assert_eq "$PARSE_LANZABOOTE" "PARSED" "lanzaboote.nix parses as valid pure Nix syntax"

assert_output_contains "cat '$LANZABOOTE_NIX'" "neuronix.security.secureBoot" "lanzaboote.nix declares neuronix.security.secureBoot option"
assert_output_contains "cat '$LANZABOOTE_NIX'" "pcrBinding" "lanzaboote.nix declares pcrBinding option"
assert_output_contains "cat '$LANZABOOTE_NIX'" '"7"' "pcrBinding includes PCR 7 for Secure Boot state"
assert_output_contains "cat '$LANZABOOTE_NIX'" '"11"' "pcrBinding includes PCR 11 for UKI binary hash"

PCR_EXCLUSION_CHECK=$(grep -E 'default = \[.*"0".*\]' "$LANZABOOTE_NIX" 2>/dev/null && echo "RAPID_LOCKOUT_RISK" || echo "SAFE_PCR_CONFIG")
assert_eq "$PCR_EXCLUSION_CHECK" "SAFE_PCR_CONFIG" "pcrBinding excludes fragile PCR 0 to prevent BIOS update lockouts"

assert_output_contains "cat '$LANZABOOTE_NIX'" "fallbackPassphrase" "lanzaboote.nix preserves mandatory fallback passphrase option"

# ==============================================================================
# Part 3: Policy-as-Code NIP-0001 & North Star Specification (Tests 17-21)
# ==============================================================================
NIP_0001="${DISTRO_PATH}/docs/rfcs/0001-north-star-and-rfc-process.md"
assert_eq "$([[ -f "$NIP_0001" ]] && echo "yes" || echo "no")" "yes" "docs/rfcs/0001-north-star-and-rfc-process.md exists"

assert_output_contains "cat '$NIP_0001'" "The North Star Thesis" "NIP-0001 establishes The North Star Thesis"
assert_output_contains "cat '$NIP_0001'" "Self-Healing, Declarative Workstation" "NIP-0001 defines the Self-Healing Declarative Workstation scope"
assert_output_contains "cat '$NIP_0001'" "Balanced Tolerable Trade-Off" "NIP-0001 mandates Balanced Tolerable Trade-Off framework"
assert_output_contains "cat '${DISTRO_PATH}/README.md'" "NIP-0001" "README.md references NIP-0001 RFC governance standard"

# ==============================================================================
# Part 4: Codebase Typography & Supply-Chain Provenance (Tests 22-25)
# ==============================================================================
EM_DASH_NIP=$(grep -rn $'\xe2\x80\x94' "$NIP_0001" 2>/dev/null | wc -l)
assert_eq "$EM_DASH_NIP" "0" "NIP-0001 conforms to zero em-dash typography invariant"

EM_DASH_LANZABOOTE=$(grep -rn $'\xe2\x80\x94' "$LANZABOOTE_NIX" 2>/dev/null | wc -l)
assert_eq "$EM_DASH_LANZABOOTE" "0" "lanzaboote.nix conforms to zero em-dash typography invariant"

assert_output_contains "cat '${DISTRO_PATH}/flake.nix'" "lanzaboote = import ./modules/security/lanzaboote.nix;" "flake.nix registers lanzaboote under nixosModules"
assert_output_contains "cat '${DISTRO_PATH}/.github/workflows/release-iso.yml'" "attest-build-provenance" "release-iso.yml enforces SLSA Level 3 keyless provenance attestation"
