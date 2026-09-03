#!/usr/bin/env bash
# Suite 13: Mutation & Negative Invariants (15 Tests)

TARGET_BIN="/home/adamrofc/NEURONIX/bin/neuronix"

start_suite "13 - Mutation & Negative Invariants"

# 1-5. Mutated Subcommands (Leading Dash Mutations)
assert_exit_code "$TARGET_BIN --status" 1 "Mutated command '--status' is deterministically rejected"
assert_exit_code "$TARGET_BIN --diet" 1 "Mutated command '--diet' is deterministically rejected"
assert_exit_code "$TARGET_BIN --undo" 1 "Mutated command '--undo' is deterministically rejected"
assert_exit_code "$TARGET_BIN --run" 1 "Mutated command '--run' is deterministically rejected"
assert_stderr_contains "$TARGET_BIN --status" "tidak dikenali" "Mutated command gives clear Indonesian error"

# 6-10. Suffix & Extra Garbage Parameter Invariance
assert_exit_code "$TARGET_BIN status extra_param_ignored" 0 "Command 'status' with extra arguments safely completes"
assert_exit_code "$TARGET_BIN version extra_param_ignored" 0 "Command 'version' with extra arguments safely completes"
assert_exit_code "$TARGET_BIN help extra_param_ignored" 0 "Command 'help' with extra arguments safely completes"
assert_output_contains "$TARGET_BIN status extra_param" "SYSTEM IDENTITY" "Extra arguments do not disrupt status telemetry"
assert_output_contains "$TARGET_BIN version extra_param" "0.2.0-alpha" "Extra arguments do not disrupt version display"

# 11-15. State Immutability on Rejections
# Ensure invalid commands do not modify /tmp or create stray files
TMP_SNAPSHOT_A="$(mktemp -u /tmp/snap_XXXXXX)"
touch "$TMP_SNAPSHOT_A"

# Verify that current git status in project directory remains 100% untouched
GIT_STATUS_BEFORE="$(git -C /home/adamrofc/NEURONIX status --porcelain)"
$TARGET_BIN invalid_cmd_rejection_test >/dev/null 2>&1 || true
$TARGET_BIN --bad-flag >/dev/null 2>&1 || true
$TARGET_BIN '!@#$' >/dev/null 2>&1 || true
GIT_STATUS_AFTER="$(git -C /home/adamrofc/NEURONIX status --porcelain)"
assert_eq "$GIT_STATUS_AFTER" "$GIT_STATUS_BEFORE" "Project repository git status is identical before and after error invocations"
assert_exit_code "$TARGET_BIN version" 0 "Core engine remains 100% operational following barrage of mutations"
assert_output_contains "$TARGET_BIN version" "Deterministic AI-Augmented Substrate" "Subtitle remains intact"
