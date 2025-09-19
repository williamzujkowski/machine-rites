#!/usr/bin/env bash
# tests/lib/test_atomic.sh - Unit tests for lib/atomic.sh
#
# Tests all functions in the atomic operations library module
# Ensures proper atomic file operations and error handling

set -euo pipefail

# Load the libraries to test
source "$(dirname "${BASH_SOURCE[0]}")/../../lib/atomic.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../lib/testing.sh"

# Test function for write_atomic()
test_write_atomic_function() {
    local test_file="$TEST_TMPDIR/atomic_test.txt"
    local test_content="Hello, atomic world!"

    # Test basic atomic write
    echo "$test_content" | write_atomic "$test_file"
    assert_exists "$test_file" "Atomic write should create file"

    local actual_content
    actual_content="$(cat "$test_file")"
    assert_equals "$test_content" "$actual_content" "File content should match"

    # Test overwrite existing file
    echo "New content" | write_atomic "$test_file"
    actual_content="$(cat "$test_file")"
    assert_equals "New content" "$actual_content" "Atomic write should overwrite existing file"

    # Test write to non-existent directory
    echo "$test_content" | write_atomic "$TEST_TMPDIR/subdir/test.txt"
    assert_exists "$TEST_TMPDIR/subdir/test.txt" "Should create directory and file"

    # Test invalid target (empty)
    assert_false bash -c 'echo "test" | write_atomic ""' "Should fail with empty target"
}

# Test function for backup_file()
test_backup_file_function() {
    local source_file="$TEST_TMPDIR/source.txt"
    local backup_dir="$TEST_TMPDIR/backups"
    local backup_path

    # Create source file
    echo "Original content" > "$source_file"

    # Test backup creation
    backup_path="$(backup_file "$source_file" "$backup_dir")"
    assert_exists "$backup_path" "Backup should be created"

    local backup_content
    backup_content="$(cat "$backup_path")"
    assert_equals "Original content" "$backup_content" "Backup content should match original"

    # Test backup of non-existent file
    assert_false backup_file "/nonexistent/file.txt" "Should fail for non-existent file"

    # Test backup without specifying backup directory
    local default_backup
    default_backup="$(backup_file "$source_file")"
    assert_exists "$default_backup" "Should create backup in default location"
}

# Test function for restore_backup()
test_restore_backup_function() {
    local target_file="$TEST_TMPDIR/target.txt"
    local backup_dir="$TEST_TMPDIR/backups"

    # Create original file and backup
    echo "Original content" > "$target_file"
    backup_file "$target_file" "$backup_dir"

    # Modify original file
    echo "Modified content" > "$target_file"

    # Restore from backup
    assert_true restore_backup "$target_file" "$backup_dir" "Restore should succeed"

    local restored_content
    restored_content="$(cat "$target_file")"
    assert_equals "Original content" "$restored_content" "Restored content should match original"

    # Test restore with no backups
    assert_false restore_backup "/nonexistent/file.txt" "$backup_dir" "Should fail when no backups exist"
}

# Test function for mktemp_secure()
test_mktemp_secure_function() {
    local temp_file

    # Test secure temp file creation
    temp_file="$(mktemp_secure)"
    assert_exists "$temp_file" "Secure temp file should be created"

    # Check permissions (should be 600)
    local perms
    perms="$(stat -c "%a" "$temp_file")"
    assert_equals "600" "$perms" "Temp file should have 600 permissions"

    # Test with custom template
    temp_file="$(mktemp_secure "custom.XXXXXX")"
    assert_exists "$temp_file" "Custom template should work"
    assert_contains "$(basename "$temp_file")" "custom." "Should use custom prefix"

    # Cleanup
    rm -f "$temp_file"
}

# Test function for atomic_append()
test_atomic_append_function() {
    local test_file="$TEST_TMPDIR/append_test.txt"

    # Test append to new file
    echo "Line 1" | atomic_append "$test_file"
    assert_exists "$test_file" "File should be created"
    assert_contains "$(cat "$test_file")" "Line 1" "Should contain first line"

    # Test append to existing file
    echo "Line 2" | atomic_append "$test_file"
    local content
    content="$(cat "$test_file")"
    assert_contains "$content" "Line 1" "Should contain original content"
    assert_contains "$content" "Line 2" "Should contain appended content"

    # Test append failure (invalid file)
    assert_false bash -c 'echo "test" | atomic_append ""' "Should fail with empty filename"
}

# Test function for atomic_replace()
test_atomic_replace_function() {
    local test_file="$TEST_TMPDIR/replace_test.txt"

    # Create test file with content
    echo "Hello old world" > "$test_file"

    # Test replacement
    assert_true atomic_replace "$test_file" "old" "new" "Replace should succeed"

    local content
    content="$(cat "$test_file")"
    assert_equals "Hello new world" "$content" "Content should be replaced"

    # Test replacement in non-existent file
    assert_false atomic_replace "/nonexistent/file.txt" "old" "new" "Should fail for non-existent file"

    # Test with invalid arguments
    assert_false atomic_replace "$test_file" "" "new" "Should fail with empty search"
    assert_false atomic_replace "$test_file" "old" "" "Should fail with empty replace"
}

# Test function for cleanup_temp_files()
test_cleanup_temp_files_function() {
    local temp_dir="$TEST_TMPDIR/cleanup_test"
    mkdir -p "$temp_dir"

    # Create some temp files
    touch "$temp_dir/file1.tmp"
    touch "$temp_dir/file2.tmp"
    touch "$temp_dir/keep.txt"

    # Set old timestamps to trigger cleanup
    touch -t 202301010000 "$temp_dir/file1.tmp" "$temp_dir/file2.tmp"

    # Test cleanup
    cleanup_temp_files "$temp_dir" "*.tmp"

    # Check results
    assert_not_exists "$temp_dir/file1.tmp" "Old temp files should be cleaned"
    assert_not_exists "$temp_dir/file2.tmp" "Old temp files should be cleaned"
    assert_exists "$temp_dir/keep.txt" "Non-temp files should remain"
}

# Test error handling and edge cases
test_error_handling() {
    # Test write_atomic with read-only directory (if not root)
    if [[ $EUID -ne 0 ]]; then
        local readonly_dir="$TEST_TMPDIR/readonly"
        mkdir -p "$readonly_dir"
        chmod 555 "$readonly_dir"

        assert_false bash -c 'echo "test" | write_atomic "'$readonly_dir'/test.txt"' \
            "Should fail writing to read-only directory"

        # Restore permissions for cleanup
        chmod 755 "$readonly_dir"
    fi

    # Test backup_file with missing parent directory
    local deep_path="$TEST_TMPDIR/missing/very/deep/backup"
    local test_file="$TEST_TMPDIR/backup_source.txt"
    echo "test" > "$test_file"

    # Should create the directory and succeed
    assert_true backup_file "$test_file" "$deep_path" "Should create backup directory structure"
}

# Test library metadata
test_library_metadata() {
    assert_equals "1.0.0" "$LIB_ATOMIC_VERSION" "Library version should be set"
    assert_equals "1" "$LIB_ATOMIC_LOADED" "Library loaded flag should be set"
    assert_equals "1" "$__LIB_ATOMIC_LOADED" "Library guard should be set"
}

# Test source guard functionality
test_source_guard() {
    # Test that sourcing again is safe
    local before_functions after_functions

    before_functions="$(declare -F | grep -c write_atomic || echo 0)"
    source "$(dirname "${BASH_SOURCE[0]}")/../../lib/atomic.sh"
    after_functions="$(declare -F | grep -c write_atomic || echo 0)"

    assert_equals "$before_functions" "$after_functions" "Re-sourcing should not duplicate functions"
}

# Test atomic operations under concurrent access
test_concurrent_operations() {
    local test_file="$TEST_TMPDIR/concurrent_test.txt"
    local temp_script="$TEST_TMPDIR/concurrent_writer.sh"

    # Create a script that writes to the same file
    cat > "$temp_script" << 'EOF'
#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../../lib/atomic.sh"
for i in {1..10}; do
    echo "Process $$ iteration $i" | write_atomic "$1"
    sleep 0.01
done
EOF
    chmod +x "$temp_script"

    # Run multiple writers concurrently
    "$temp_script" "$test_file" &
    "$temp_script" "$test_file" &
    "$temp_script" "$test_file" &
    wait

    # File should exist and contain valid content
    assert_exists "$test_file" "File should exist after concurrent writes"
    assert_true test -s "$test_file" "File should not be empty"

    # Content should be from one complete write (not corrupted)
    local content
    content="$(cat "$test_file")"
    assert_matches "$content" "^Process [0-9]+ iteration [0-9]+$" "Content should be from one complete write"
}

# Main test runner
main() {
    echo "Testing lib/atomic.sh..."

    run_tests \
        test_write_atomic_function \
        test_backup_file_function \
        test_restore_backup_function \
        test_mktemp_secure_function \
        test_atomic_append_function \
        test_atomic_replace_function \
        test_cleanup_temp_files_function \
        test_error_handling \
        test_library_metadata \
        test_source_guard \
        test_concurrent_operations
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi