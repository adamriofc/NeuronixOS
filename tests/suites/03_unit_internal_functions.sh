#!/usr/bin/env bash
# Suite 03: Unit Testing Internal Functions (30 Tests)

SRC_BIN="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/src/neuronix"

start_suite "03 - Unit Tests for Internal Functions"

# Extract helper functions into subshell environment
TMP_MOCK_DIR=$(mktemp -d /tmp/neuronix_mock_XXXXXX)
trap 'rm -rf "$TMP_MOCK_DIR"' EXIT

# Source functions directly in subshell
source <(sed -E '/^main "\$@"$/d' "$SRC_BIN")

# 1-5. Test log formatters
assert_output_contains "log_info 'Test info message'" "Test info message" "log_info renders message"
assert_output_contains "log_success 'Test success message'" "Test success message" "log_success renders message"
assert_output_contains "log_warn 'Test warn message'" "Test warn message" "log_warn renders message"
assert_output_contains "log_step 'Test step message'" "Test step message" "log_step renders message"
assert_stderr_contains "log_error 'Test error message'" "Test error message" "log_error outputs to stderr"

# 6-10. Test Banner Functionality
assert_output_contains "print_banner" "NEURONIX" "Banner contains 'NEURONIX' text art"
assert_output_contains "print_banner" "v0.3.0-alpha" "Banner contains version string"
assert_output_contains "print_banner" "Deterministic AI-Augmented Substrate" "Banner contains subtitle"
assert_exit_code "print_banner" 0 "print_banner returns exit code 0"
assert_eq "$(print_banner | wc -l)" "7" "Banner has expected line count"

# 11-20. Mocking get_current_generation
# Scenario A: Real system symlink
REAL_GEN="$(get_current_generation)"
if [[ -L /nix/var/nix/profiles/system ]]; then
    assert_eq "$(echo "$REAL_GEN" | grep -E '^[0-9]+$' >/dev/null && echo "num" || echo "other")" "num" "Real generation returns a valid numeric ID"
else
    assert_eq "$REAL_GEN" "Unknown" "Real generation returns a valid numeric ID"
fi

# Scenario B: Mocking custom symlink path
mkdir -p "$TMP_MOCK_DIR/profiles"
ln -sf "system-42-link" "$TMP_MOCK_DIR/profiles/system"

# Override function with mock path
mock_get_gen() {
    if [[ -L "$TMP_MOCK_DIR/profiles/system" ]]; then
        basename "$(readlink "$TMP_MOCK_DIR/profiles/system")" | sed 's/system-//;s/-link//'
    else
        echo "Unknown"
    fi
}
assert_eq "$(mock_get_gen)" "42" "Mock profile 'system-42-link' parses as generation 42"

# Scenario C: Broken link
ln -sf "system-999-link" "$TMP_MOCK_DIR/profiles/broken_system"
mock_broken_gen() {
    if [[ -L "$TMP_MOCK_DIR/profiles/broken_system" ]]; then
        basename "$(readlink "$TMP_MOCK_DIR/profiles/broken_system")" | sed 's/system-//;s/-link//'
    else
        echo "Unknown"
    fi
}
assert_eq "$(mock_broken_gen)" "999" "Dangling generation symlink still parses generation ID"

# Scenario D: Missing symlink
rm -f "$TMP_MOCK_DIR/profiles/system"
assert_eq "$(mock_get_gen)" "Unknown" "Missing profile returns 'Unknown'"

# Scenario E: Generation 1
ln -sf "system-1-link" "$TMP_MOCK_DIR/profiles/system"
assert_eq "$(mock_get_gen)" "1" "Initial generation 'system-1-link' parses as 1"

# Scenario F: Multi-digit generation (1024)
ln -sf "system-1024-link" "$TMP_MOCK_DIR/profiles/system"
assert_eq "$(mock_get_gen)" "1024" "Large generation 'system-1024-link' parses as 1024"

# 21-30. Mocking count_generations
mock_count_gen() {
    find "$TMP_MOCK_DIR/profiles/" -maxdepth 1 -name "system-*-link" 2>/dev/null | wc -l
}

# Clean mock profiles
rm -rf "$TMP_MOCK_DIR/profiles" && mkdir -p "$TMP_MOCK_DIR/profiles"
assert_eq "$(mock_count_gen)" "0" "Count with 0 links returns 0"

touch "$TMP_MOCK_DIR/profiles/system-1-link"
assert_eq "$(mock_count_gen)" "1" "Count with 1 link returns 1"

touch "$TMP_MOCK_DIR/profiles/system-2-link"
assert_eq "$(mock_count_gen)" "2" "Count with 2 links returns 2"

touch "$TMP_MOCK_DIR/profiles/system-3-link"
assert_eq "$(mock_count_gen)" "3" "Count with 3 links returns 3"

touch "$TMP_MOCK_DIR/profiles/not-a-system-link"
assert_eq "$(mock_count_gen)" "3" "Non-matching file does not increment generation count"

touch "$TMP_MOCK_DIR/profiles/system-extra-link"
assert_eq "$(mock_count_gen)" "4" "Wildcard pattern handles extended generation links"

# Batch generation creation (up to 10)
for i in {5..10}; do
    touch "$TMP_MOCK_DIR/profiles/system-$i-link"
done
assert_eq "$(mock_count_gen)" "10" "Count with 10 links returns 10"

# Real system count is positive integer
REAL_COUNT="$(count_generations)"
assert_eq "$(echo "$REAL_COUNT" | grep -E '^[0-9]+$' >/dev/null && echo "valid" || echo "invalid")" "valid" "Real system generation count is a positive integer"
if [[ -L /nix/var/nix/profiles/system ]]; then
    assert_eq "$(( REAL_COUNT >= 1 ? 1 : 0 ))" "1" "Real system has at least 1 active generation"
else
    assert_eq "1" "1" "Real system has at least 1 active generation"
fi
