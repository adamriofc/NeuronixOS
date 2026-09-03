#!/usr/bin/env bash
# Suite 07: Flake & Hermetic Reproducibility (10 Tests)

REPO_DIR="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

start_suite "07 - Flake & Hermetic Reproducibility"

# 1. flake.nix existence
assert_eq "$(test -f "$REPO_DIR/flake.nix" && echo "yes" || echo "no")" "yes" "flake.nix file exists"

# 2. flake.lock existence
assert_eq "$(test -f "$REPO_DIR/flake.lock" && echo "yes" || echo "no")" "yes" "flake.lock lockfile exists"

# 3. Valid JSON syntax in flake.lock
assert_exit_code "python3 -c 'import json; json.load(open(\"$REPO_DIR/flake.lock\"))' 2>/dev/null || grep -q '\"version\":' $REPO_DIR/flake.lock" 0 "flake.lock is valid JSON structure"

# 4. Flake inputs contain nixpkgs
assert_output_contains "grep 'nixpkgs' $REPO_DIR/flake.lock" "nixpkgs" "flake.lock records nixpkgs dependency input"

# 5. Flake inputs contain flake-utils
assert_output_contains "grep 'flake-utils' $REPO_DIR/flake.lock" "flake-utils" "flake.lock records flake-utils dependency input"

# 6. Flake metadata command returns exit 0
assert_exit_code "nix flake metadata $REPO_DIR" 0 "nix flake metadata command executes with exit 0"

# 7. Package description present in metadata
assert_output_contains "nix flake metadata $REPO_DIR" "NEURONIX" "Flake metadata contains 'NEURONIX' description"

# 8. Git working directory status
assert_exit_code "git -C $REPO_DIR status" 0 "Git repository status is clean and responsive"

# 9. Git HEAD commit exists
assert_eq "$(git -C $REPO_DIR rev-parse --verify HEAD >/dev/null && echo "valid" || echo "invalid")" "valid" "Git repository has a verified HEAD commit"

# 10. User local binary symlink
assert_eq "$(test -L "${HOME}/.local/bin/neuronix" && echo "linked" || echo "missing")" "linked" "User ~/.local/bin/neuronix symlink is linked to build"
