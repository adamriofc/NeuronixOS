#!/usr/bin/env bash
# Suite 09: Boundary, Buffer & Property-Based Fuzzing (50 Tests)

TARGET_BIN="/home/adamrofc/NEURONIX/bin/neuronix"

start_suite "09 - Boundary, Buffer & Property-Based Fuzzing"

# 1-10. Buffer Overflow & Giant Argument Fuzzing
for len in 500 1000 2000 5000 10000; do
    GIANT_ARG=$(printf 'A%.0s' $(seq 1 $len))
    assert_exit_code "$TARGET_BIN $GIANT_ARG" 1 "Giant argument (${len} chars) fails cleanly with exit 1 without crashing"
    assert_stderr_contains "$TARGET_BIN $GIANT_ARG" "tidak dikenali" "Giant argument (${len} chars) emits standard error message"
done

# 11-20. Control Characters & Binary Escapes Fuzzing
CTRL_CHARS=($'\x01' $'\x02' $'\x03' $'\x04' $'\x07' $'\x08' $'\x0B' $'\x0C' $'\x0E' $'\x1B')
for i in "${!CTRL_CHARS[@]}"; do
    char="${CTRL_CHARS[$i]}"
    assert_exit_code "$TARGET_BIN 'test${char}fuzz'" 1 "Control character index ${i} safely rejected with exit code 1"
done

# 21-30. Shell Wildcard & Globbing Expansion Fuzzing
GLOBS=('*' '?' '[a-z]' '[0-9]' '{a,b,c}' '/*' '/**/*' '~' '$' '^')
for glob_pattern in "${GLOBS[@]}"; do
    assert_exit_code "$TARGET_BIN '$glob_pattern'" 1 "Wildcard pattern '$glob_pattern' safely rejected with exit code 1"
done

# 31-40. Quotes, Backticks, and Code Injection Fuzzing
INJECTIONS=(
    '$(whoami)'
    '`id`'
    '${PATH}'
    '"; echo hacked; "'
    "''"
    '"""'
    "\\\""
    '\0'
    '$(exit 0)'
    '| cat'
)
for inj in "${INJECTIONS[@]}"; do
    assert_exit_code "$TARGET_BIN '$inj'" 1 "Injection string '$inj' safely rejected without executing subshell"
done

# 41-50. Dash & Hyphen Permutation Fuzzing
DASH_PERMUTATIONS=(
    "-"
    "--"
    "---"
    "----"
    "-----"
    "--help-me"
    "-help"
    "-version"
    "--v"
    "-status"
)
for dash_arg in "${DASH_PERMUTATIONS[@]}"; do
    assert_exit_code "$TARGET_BIN '$dash_arg'" 1 "Dash permutation '$dash_arg' safely handled with exit code 1"
done
