#!/usr/bin/env bash
# Suite 08: Environment Poisoning & Isolation Defense (30 Tests)

TARGET_BIN="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/bin/neuronix"

start_suite "08 - Environment Poisoning & Variable Sanitization"

# 1-5. Stripped Environment (env -i)
assert_exit_code "env -i $TARGET_BIN version" 0 "Running in stripped environment (env -i) executes version cleanly"
assert_exit_code "env -i $TARGET_BIN help" 0 "Running in stripped environment (env -i) executes help cleanly"
assert_exit_code "env -i $TARGET_BIN status" 0 "Running in stripped environment (env -i) executes status cleanly"
assert_output_contains "env -i $TARGET_BIN version" "0.4.0-beta" "Stripped env retains version metadata"
assert_output_contains "env -i $TARGET_BIN status" "SYSTEM IDENTITY" "Stripped env executes core telemetry logic"

# 6-10. Poisoned PATH
BASH_EXEC="$(command -v bash)"
assert_exit_code "PATH='' $BASH_EXEC $TARGET_BIN version" 0 "Empty PATH fallback executes version with exit 0"
assert_exit_code "PATH='/nonexistent_dir_xyz' $BASH_EXEC $TARGET_BIN help" 0 "Bogus PATH fallback executes help with exit 0"
assert_exit_code "PATH='/tmp' $BASH_EXEC $TARGET_BIN status" 0 "Restricted PATH fallback executes status with exit 0"
assert_output_contains "PATH='' $BASH_EXEC $TARGET_BIN version" "Apache License" "Empty PATH preserves version output"
assert_output_contains "PATH='/fake' $BASH_EXEC $TARGET_BIN status" "STORAGE SUBSYSTEM" "Restricted PATH preserves storage output"

# 11-15. Poisoned HOME Directory
assert_exit_code "HOME='/dev/null' $TARGET_BIN version" 0 "Poisoned HOME=/dev/null executes version with exit 0"
assert_exit_code "HOME='/proc/nonexistent' $TARGET_BIN help" 0 "Non-existent HOME executes help with exit 0"
assert_exit_code "HOME='' $TARGET_BIN status" 0 "Empty HOME executes status with exit 0"
assert_output_contains "HOME='/dev/null' $TARGET_BIN help" "USAGE:" "Poisoned HOME displays help correctly"
assert_output_contains "HOME='' $TARGET_BIN status" "Kernel" "Empty HOME displays telemetry correctly"

# 16-20. Poisoned Locale & Encoding Variables
assert_exit_code "LANG='C' $TARGET_BIN version" 0 "LANG=C executes version cleanly"
assert_exit_code "LC_ALL='C' $TARGET_BIN help" 0 "LC_ALL=C executes help cleanly"
assert_exit_code "LC_ALL='POSIX' $TARGET_BIN status" 0 "LC_ALL=POSIX executes status cleanly"
assert_exit_code "LANG='invalid_locale_xyz.UTF-8' $TARGET_BIN version" 0 "Invalid locale executes version cleanly"
assert_output_contains "LC_ALL='C' $TARGET_BIN version" "0.4.0-beta" "LC_ALL=C preserves output integrity"

# 21-25. Poisoned Terminal & Shell Variables
assert_exit_code "TERM='' $TARGET_BIN version" 0 "Empty TERM variable executes version with exit 0"
assert_exit_code "TERM='xterm-256color' $TARGET_BIN status" 0 "Modern TERM executes status with exit 0"
assert_exit_code "SHELL='/bin/sh' $TARGET_BIN help" 0 "SHELL=/bin/sh executes help with exit 0"
assert_exit_code "SHELL='' $TARGET_BIN version" 0 "Empty SHELL executes version with exit 0"
assert_output_contains "TERM='' $TARGET_BIN help" "CORE COMMANDS:" "Empty TERM renders help text cleanly"

# 26-30. Poisoned TMPDIR & Scratch Storage
assert_exit_code "TMPDIR='/dev/null' $TARGET_BIN version" 0 "TMPDIR=/dev/null executes version with exit 0"
assert_exit_code "TMPDIR='/root/forbidden' $TARGET_BIN help" 0 "Unwritable TMPDIR executes help with exit 0"
assert_exit_code "TMPDIR='' $TARGET_BIN status" 0 "Empty TMPDIR executes status with exit 0"
assert_output_contains "TMPDIR='/dev/null' $TARGET_BIN version" "Substrate" "Poisoned TMPDIR preserves version metadata"
assert_output_contains "TMPDIR='/root/forbidden' $TARGET_BIN status" "NixOS" "Unwritable TMPDIR preserves telemetry output"
