#!/usr/bin/env bash
# Semantic NixOS desktop checks; no builds, installs, or writable Nix store.
# First fetch the flake inputs in your normal development/CI environment, then:
# NIXPKGS_SOURCE=/path/to/pinned/nixpkgs bash tests/test_desktop_session.sh
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
nix_bin="${NIX_BIN:-nix}"
if [[ -z "${NIXPKGS_SOURCE:-}" || ! -f "$NIXPKGS_SOURCE/flake.nix" ]]; then
    echo "Set NIXPKGS_SOURCE to an existing nixpkgs source matching flake.lock." >&2
    echo "This test intentionally does not fetch inputs or write to /nix." >&2
    exit 2
fi

# Keep every scratch/cache write on the project's filesystem (Drive_D locally).
scratch="$project_root/.cache/desktop-session"
mkdir -p "$scratch/tmp" "$scratch/xdg"
export TMPDIR="$scratch/tmp"
export XDG_CACHE_HOME="$scratch/xdg"
export NIXPKGS_SOURCE

expected_hash="$(python3 - "$project_root/flake.lock" <<'PY'
import json, sys
with open(sys.argv[1]) as lock:
    print(json.load(lock)["nodes"]["nixpkgs"]["locked"]["narHash"])
PY
)"
actual_hash="$("$nix_bin" --extra-experimental-features nix-command --store dummy:// hash path "$NIXPKGS_SOURCE")"
if [[ "$actual_hash" != "$expected_hash" ]]; then
    echo "NIXPKGS_SOURCE does not match the pinned flake.lock NAR hash." >&2
    exit 2
fi

result="$(mktemp "$scratch/result.XXXXXX.json")"
generated_root="$(mktemp -d "$scratch/generated.XXXXXX")"
trap 'rm -f "$result"; rm -rf "$generated_root"' EXIT
DRY_RUN=1 TARGET_ROOT="$generated_root" TARGET_HOSTNAME=neuronix-test \
    TARGET_USER=alice TARGET_ARCH=x86_64 SELECTED_DESKTOP=neuronix \
    bash "$project_root/installer/scripts/neuronix-install-engine.sh" > "$generated_root/generation.log"
export NEURONIX_TEST_GENERATED_ROOT="$generated_root"
"$nix_bin" --extra-experimental-features 'nix-command flakes' \
    --store dummy:// eval --read-only --impure --json \
    --file "$project_root/tests/desktop-session.nix" \
    --apply 'test: test { nixpkgsSource = builtins.getEnv "NIXPKGS_SOURCE"; generatedRoot = builtins.getEnv "NEURONIX_TEST_GENERATED_ROOT"; }' > "$result"

python3 - "$result" <<'PY'
import json, sys
with open(sys.argv[1]) as stream:
    report = json.load(stream)
for target, result in report["results"].items():
    failed = result["failures"]
    print(f'{"FAIL" if failed else "PASS"} {target}: '
          f'{len(result["checks"]) - len(failed)}/{len(result["checks"])} invariants')
    for description in failed:
        print(f"  FAIL {description}")
print(f'Evaluated {report["total"]} desktop-session invariants; no packages built.')
sys.exit(0 if report["passed"] else 1)
PY
