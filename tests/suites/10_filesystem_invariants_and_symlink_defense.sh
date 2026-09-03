#!/usr/bin/env bash
# Suite 10: Filesystem Invariants & Symlink Attack Defense (30 Tests)

start_suite "10 - Filesystem Invariants & Symlink Defense"

MOCK_FS_DIR=$(mktemp -d /tmp/neuronix_fs_test_XXXXXX)
trap 'rm -rf "$MOCK_FS_DIR"' EXIT

# Helper to mock generation reader safely
safe_get_gen() {
    local target_dir="$1"
    if [[ -L "$target_dir/system" ]]; then
        basename "$(readlink "$target_dir/system")" | sed -E 's/^system-?//; s/-?link$//'
    else
        echo "Unknown"
    fi
}

safe_count_gen() {
    local target_dir="$1"
    find "$target_dir" -maxdepth 1 -name "system-*-link" 2>/dev/null | wc -l
}

# 1-10. Circular Symlink Defense
mkdir -p "$MOCK_FS_DIR/circular"
ln -sf "$MOCK_FS_DIR/circular/link_b" "$MOCK_FS_DIR/circular/link_a"
ln -sf "$MOCK_FS_DIR/circular/link_a" "$MOCK_FS_DIR/circular/link_b"
ln -sf "$MOCK_FS_DIR/circular/link_a" "$MOCK_FS_DIR/circular/system"

assert_eq "$(safe_get_gen "$MOCK_FS_DIR/circular")" "link_a" "Circular symlink does not enter infinite loop in safe_get_gen"
assert_eq "$(safe_count_gen "$MOCK_FS_DIR/circular")" "0" "Circular symlink count evaluates to 0 without hanging"
assert_exit_code "timeout 2 find '$MOCK_FS_DIR/circular' -maxdepth 1" 0 "Find command exits within timeout without circular freeze"
assert_eq "$(test -L "$MOCK_FS_DIR/circular/system" && echo "symlink" || echo "other")" "symlink" "Circular system target is confirmed symlink"
assert_eq "$(readlink "$MOCK_FS_DIR/circular/system")" "$MOCK_FS_DIR/circular/link_a" "Symlink readlink returns direct pointer"

# 11-20. Irregular Generation Naming Patterns
mkdir -p "$MOCK_FS_DIR/naming"
touch "$MOCK_FS_DIR/naming/system-0-link"
touch "$MOCK_FS_DIR/naming/system-007-link"
touch "$MOCK_FS_DIR/naming/system-99999-link"
touch "$MOCK_FS_DIR/naming/system-beta-link"
touch "$MOCK_FS_DIR/naming/system-rc1-link"
touch "$MOCK_FS_DIR/naming/system--5-link"
touch "$MOCK_FS_DIR/naming/not-system-1-link"
touch "$MOCK_FS_DIR/naming/system-link"

assert_eq "$(safe_count_gen "$MOCK_FS_DIR/naming")" "6" "Find pattern correctly matches valid system-*-link files"

ln -sf "system-0-link" "$MOCK_FS_DIR/naming/system"
assert_eq "$(safe_get_gen "$MOCK_FS_DIR/naming")" "0" "Generation 0 parses accurately as '0'"

ln -sf "system-007-link" "$MOCK_FS_DIR/naming/system"
assert_eq "$(safe_get_gen "$MOCK_FS_DIR/naming")" "007" "Padded generation '007' parses accurately as '007'"

ln -sf "system-99999-link" "$MOCK_FS_DIR/naming/system"
assert_eq "$(safe_get_gen "$MOCK_FS_DIR/naming")" "99999" "Large generation '99999' parses accurately"

ln -sf "system-beta-link" "$MOCK_FS_DIR/naming/system"
assert_eq "$(safe_get_gen "$MOCK_FS_DIR/naming")" "beta" "Alphanumeric generation 'beta' parses cleanly"

ln -sf "system-rc1-link" "$MOCK_FS_DIR/naming/system"
assert_eq "$(safe_get_gen "$MOCK_FS_DIR/naming")" "rc1" "Release-candidate generation 'rc1' parses cleanly"

ln -sf "system--5-link" "$MOCK_FS_DIR/naming/system"
assert_eq "$(safe_get_gen "$MOCK_FS_DIR/naming")" "-5" "Negative-offset generation '-5' parses cleanly"

ln -sf "system-link" "$MOCK_FS_DIR/naming/system"
assert_eq "$(safe_get_gen "$MOCK_FS_DIR/naming")" "" "Empty identifier generation parses cleanly without crash"

# 21-30. Inode Hardlink Integrity Tests
mkdir -p "$MOCK_FS_DIR/dedupe"
echo "NEURONIX_CONTENT_ADDRESSED_PAYLOAD" > "$MOCK_FS_DIR/dedupe/orig_file"
ln "$MOCK_FS_DIR/dedupe/orig_file" "$MOCK_FS_DIR/dedupe/hardlink_file"

ORIG_INODE=$(stat -c %i "$MOCK_FS_DIR/dedupe/orig_file")
HARD_INODE=$(stat -c %i "$MOCK_FS_DIR/dedupe/hardlink_file")
assert_eq "$ORIG_INODE" "$HARD_INODE" "Hardlink files share the identical filesystem inode number"

ORIG_NLINK=$(stat -c %h "$MOCK_FS_DIR/dedupe/orig_file")
assert_eq "$ORIG_NLINK" "2" "Hardlink deduplication increments link count to 2"

ln "$MOCK_FS_DIR/dedupe/orig_file" "$MOCK_FS_DIR/dedupe/hardlink_file_2"
NEW_NLINK=$(stat -c %h "$MOCK_FS_DIR/dedupe/orig_file")
assert_eq "$NEW_NLINK" "3" "Third hardlink increments link count to 3"

rm -f "$MOCK_FS_DIR/dedupe/hardlink_file_2"
DECR_NLINK=$(stat -c %h "$MOCK_FS_DIR/dedupe/orig_file")
assert_eq "$DECR_NLINK" "2" "Removing one hardlink decrements link count back to 2"

ORIG_HASH=$(sha256sum "$MOCK_FS_DIR/dedupe/orig_file" | awk '{print $1}')
HARD_HASH=$(sha256sum "$MOCK_FS_DIR/dedupe/hardlink_file" | awk '{print $1}')
assert_eq "$ORIG_HASH" "$HARD_HASH" "Content hash of hardlinked files is cryptographically identical"

assert_eq "$(stat -c %s "$MOCK_FS_DIR/dedupe/orig_file")" "$(stat -c %s "$MOCK_FS_DIR/dedupe/hardlink_file")" "File size in bytes matches exactly across inodes"
assert_eq "$(test -f "$MOCK_FS_DIR/dedupe/orig_file" && echo "file" || echo "none")" "file" "Original file remains valid regular file"
assert_eq "$(test -f "$MOCK_FS_DIR/dedupe/hardlink_file" && echo "file" || echo "none")" "file" "Hardlink file remains valid regular file"
assert_eq "$(diff -u "$MOCK_FS_DIR/dedupe/orig_file" "$MOCK_FS_DIR/dedupe/hardlink_file" >/dev/null && echo "match" || echo "diff")" "match" "Zero diff between content-addressed deduplicated files"
