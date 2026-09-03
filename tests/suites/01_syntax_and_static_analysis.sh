#!/usr/bin/env bash
# Suite 01: Syntax, Static Analysis, and POSIX Compliance (15 Tests)

SRC_BIN="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/src/neuronix"
TARGET_BIN="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/bin/neuronix"

start_suite "01 - Syntax & Static Analysis"

# 1. Source file exists
assert_eq "$(test -f "$SRC_BIN" && echo "yes" || echo "no")" "yes" "Source script exists"

# 2. Source file is executable
assert_eq "$(test -x "$SRC_BIN" && echo "yes" || echo "no")" "yes" "Source script is executable"

# 3. Target symlink exists
assert_eq "$(test -L "$TARGET_BIN" && echo "yes" || echo "no")" "yes" "Bin symlink exists"

# 4. Target symlink resolves to source
assert_eq "$(readlink -f "$TARGET_BIN")" "$(readlink -f "$SRC_BIN")" "Bin symlink resolves correctly"

# 5. Bash syntax validation
assert_exit_code "bash -n $SRC_BIN" 0 "Bash -n returns 0 syntax errors"

# 6. Shebang validation
assert_eq "$(head -n 1 "$SRC_BIN")" "#!/usr/bin/env bash" "Shebang is exactly '#!/usr/bin/env bash'"

# 7. Strict mode validation: pipefail
assert_output_contains "grep -E 'set -.*pipefail' $SRC_BIN" "pipefail" "Strict mode includes pipefail"

# 8. Strict mode validation: errexit (-e)
assert_output_contains "grep -E 'set -.*e' $SRC_BIN" "set -e" "Strict mode includes errexit"

# 9. No trailing carriage returns (CRLF)
assert_eq "$(grep -U $'\r' "$SRC_BIN" | wc -l)" "0" "No Windows CRLF line endings present"

# 10. File encoding is UTF-8 / ASCII
assert_eq "$(iconv -f UTF-8 -t UTF-8 "$SRC_BIN" >/dev/null && echo "valid-utf8")" "valid-utf8" "File encoding is clean valid UTF-8/ASCII"

# 11. No hardcoded sudo paths
assert_output_not_contains "grep '/usr/bin/sudo' $SRC_BIN" "/usr/bin/sudo" "No hardcoded /usr/bin/sudo"

# 12. No hardcoded /usr/bin/python
assert_output_not_contains "grep '/usr/bin/python' $SRC_BIN" "/usr/bin/python" "No hardcoded /usr/bin/python"

# 13. License header check
assert_output_contains "head -n 10 $SRC_BIN" "Apache License, Version 2.0" "Apache 2.0 header in source"

# 14. Version variable definition
assert_output_contains "grep 'VERSION=' $SRC_BIN" "VERSION=" "VERSION variable declared"

# 15. Program name variable definition
assert_output_contains "grep 'PROGRAM_NAME=' $SRC_BIN" "PROGRAM_NAME=" "PROGRAM_NAME variable declared"
