#!/usr/bin/env bash
# tests/lib/test_validation.sh - Unit tests for lib/validation.sh
#
# Tests all functions in the validation library module
# Ensures proper input validation and sanitization

set -euo pipefail

# Load the libraries to test
source "$(dirname "${BASH_SOURCE[0]}")/../../lib/validation.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../lib/testing.sh"

# Test function for validate_email()
test_validate_email_function() {
    # Test valid emails
    assert_true validate_email "user@example.com" "Simple email should be valid"
    assert_true validate_email "test.user+tag@example.co.uk" "Complex email should be valid"
    assert_true validate_email "123@example.org" "Numeric user should be valid"

    # Test invalid emails
    assert_false validate_email "invalid.email" "Email without @ should be invalid"
    assert_false validate_email "@example.com" "Email without user should be invalid"
    assert_false validate_email "user@" "Email without domain should be invalid"
    assert_false validate_email "user@.com" "Email with invalid domain should be invalid"
    assert_false validate_email "" "Empty email should be invalid"

    # Test email length limits
    local long_email="$(printf '%*s' 250 | tr ' ' 'a')@example.com"
    assert_false validate_email "$long_email" "Overly long email should be invalid"
}

# Test function for validate_url()
test_validate_url_function() {
    # Test valid URLs
    assert_true validate_url "https://example.com" "HTTPS URL should be valid"
    assert_true validate_url "http://example.com" "HTTP URL should be valid"
    assert_true validate_url "https://example.com/path?query=value#fragment" "Complex URL should be valid"
    assert_true validate_url "http://localhost:8080" "Localhost URL should be valid"

    # Test invalid URLs
    assert_false validate_url "ftp://example.com" "FTP URL should be invalid"
    assert_false validate_url "example.com" "URL without protocol should be invalid"
    assert_false validate_url "https://" "Incomplete URL should be invalid"
    assert_false validate_url "" "Empty URL should be invalid"

    # Test URL length limits
    local long_url="https://example.com/$(printf '%*s' 2100 | tr ' ' 'a')"
    assert_false validate_url "$long_url" "Overly long URL should be invalid"
}

# Test function for validate_path()
test_validate_path_function() {
    local test_file="$TEST_TMPDIR/test_file.txt"
    local test_dir="$TEST_TMPDIR/test_dir"

    # Create test file and directory
    echo "test" > "$test_file"
    mkdir -p "$test_dir"

    # Test valid paths
    assert_true validate_path "$test_file" "file" "Existing file should be valid"
    assert_true validate_path "$test_dir" "dir" "Existing directory should be valid"
    assert_true validate_path "$test_file" "any" "Existing file should be valid for any type"
    assert_true validate_path "/nonexistent/path" "any" "Non-existent path should be valid for any type"

    # Test invalid paths
    assert_false validate_path "$test_file" "dir" "File should not be valid as directory"
    assert_false validate_path "$test_dir" "file" "Directory should not be valid as file"
    assert_false validate_path "../../../etc/passwd" "any" "Path with traversal should be invalid"
    assert_false validate_path "path//with//double//slashes" "any" "Path with double slashes should be invalid"
    assert_false validate_path "$(printf 'path/%.0s' {1..1000})" "any" "Overly long path should be invalid"

    # Test with newlines and control characters
    assert_false validate_path $'path\nwith\nnewlines' "any" "Path with newlines should be invalid"
    assert_false validate_path $'path\rwith\rcarriage' "any" "Path with carriage returns should be invalid"
}

# Test function for validate_hostname()
test_validate_hostname_function() {
    # Test valid hostnames
    assert_true validate_hostname "example.com" "Simple hostname should be valid"
    assert_true validate_hostname "sub.example.com" "Subdomain should be valid"
    assert_true validate_hostname "test-host" "Hostname with hyphen should be valid"
    assert_true validate_hostname "a" "Single character hostname should be valid"

    # Test invalid hostnames
    assert_false validate_hostname "-example.com" "Hostname starting with hyphen should be invalid"
    assert_false validate_hostname "example-.com" "Hostname ending with hyphen should be invalid"
    assert_false validate_hostname "exam_ple.com" "Hostname with underscore should be invalid"
    assert_false validate_hostname "" "Empty hostname should be invalid"

    # Test length limits
    local long_hostname="$(printf '%*s' 260 | tr ' ' 'a').com"
    assert_false validate_hostname "$long_hostname" "Overly long hostname should be invalid"

    local long_label="$(printf '%*s' 70 | tr ' ' 'a')"
    assert_false validate_hostname "$long_label.com" "Hostname with overly long label should be invalid"
}

# Test function for validate_port()
test_validate_port_function() {
    # Test valid ports
    assert_true validate_port "80" "HTTP port should be valid"
    assert_true validate_port "443" "HTTPS port should be valid"
    assert_true validate_port "8080" "Common alternative port should be valid"
    assert_true validate_port "1" "Minimum port should be valid"
    assert_true validate_port "65535" "Maximum port should be valid"

    # Test invalid ports
    assert_false validate_port "0" "Port 0 should be invalid"
    assert_false validate_port "65536" "Port above maximum should be invalid"
    assert_false validate_port "-1" "Negative port should be invalid"
    assert_false validate_port "abc" "Non-numeric port should be invalid"
    assert_false validate_port "" "Empty port should be invalid"
    assert_false validate_port "80.5" "Decimal port should be invalid"
}

# Test function for validate_ip()
test_validate_ip_function() {
    # Test valid IPs
    assert_true validate_ip "192.168.1.1" "Private IP should be valid"
    assert_true validate_ip "8.8.8.8" "Public IP should be valid"
    assert_true validate_ip "0.0.0.0" "Zero IP should be valid"
    assert_true validate_ip "255.255.255.255" "Broadcast IP should be valid"

    # Test invalid IPs
    assert_false validate_ip "256.1.1.1" "IP with octet > 255 should be invalid"
    assert_false validate_ip "192.168.1" "Incomplete IP should be invalid"
    assert_false validate_ip "192.168.1.1.1" "IP with too many octets should be invalid"
    assert_false validate_ip "192.168.01.1" "IP with leading zeros should be invalid"
    assert_false validate_ip "192.168.1.a" "IP with non-numeric octet should be invalid"
    assert_false validate_ip "" "Empty IP should be invalid"
}

# Test function for sanitize_filename()
test_sanitize_filename_function() {
    # Test basic sanitization
    local result
    result="$(sanitize_filename "My File!.txt")"
    assert_equals "My File_.txt" "$result" "Should replace dangerous characters"

    result="$(sanitize_filename "file/with/slashes")"
    assert_equals "file_with_slashes" "$result" "Should replace slashes"

    result="$(sanitize_filename "file<>with|dangerous:chars")"
    assert_equals "filewith_dangerous_chars" "$result" "Should remove dangerous characters"

    # Test custom replacement character
    result="$(sanitize_filename "file/name" "-")"
    assert_equals "file-name" "$result" "Should use custom replacement character"

    # Test length limiting
    local long_name="$(printf '%*s' 300 | tr ' ' 'a')"
    result="$(sanitize_filename "$long_name")"
    assert_true test ${#result} -le 255 "Should limit filename length"

    # Test empty input protection
    result="$(sanitize_filename "")"
    assert_equals "file" "$result" "Should provide default for empty input"
}

# Test function for is_safe_string()
test_is_safe_string_function() {
    # Test safe strings
    assert_true is_safe_string "hello world" "Simple text should be safe"
    assert_true is_safe_string "file.txt" "Filename should be safe"
    assert_true is_safe_string "user@example.com" "Email should be safe"

    # Test unsafe strings
    assert_false is_safe_string "rm -rf /" "Dangerous command should be unsafe"
    assert_false is_safe_string "echo \$(whoami)" "Command substitution should be unsafe"
    assert_false is_safe_string "echo \`date\`" "Backticks should be unsafe"
    assert_false is_safe_string "cmd1; cmd2" "Command separator should be unsafe"
    assert_false is_safe_string "cmd1 | cmd2" "Pipe should be unsafe"
    assert_false is_safe_string "cmd1 && cmd2" "Background should be unsafe"
    assert_false is_safe_string "cmd > file" "Redirect should be unsafe"
    assert_false is_safe_string $'string\nwith\nnewlines' "Newlines should be unsafe"

    # Test length limits
    local long_string="$(printf '%*s' 2000 | tr ' ' 'a')"
    assert_false is_safe_string "$long_string" "Overly long string should be unsafe"
}

# Test function for validate_version()
test_validate_version_function() {
    # Test valid versions
    assert_true validate_version "1.0.0" "Semantic version should be valid"
    assert_true validate_version "2.5.10" "Version with larger numbers should be valid"
    assert_true validate_version "1.0.0-alpha" "Pre-release version should be valid"
    assert_true validate_version "1.0.0+build.1" "Version with build metadata should be valid"
    assert_true validate_version "1.0.0-alpha.1+build.1" "Complex version should be valid"

    # Test invalid versions
    assert_false validate_version "1.0" "Two-part version should be invalid"
    assert_false validate_version "1.0.0.0" "Four-part version should be invalid"
    assert_false validate_version "v1.0.0" "Version with 'v' prefix should be invalid"
    assert_false validate_version "1.0.a" "Version with non-numeric part should be invalid"
    assert_false validate_version "" "Empty version should be invalid"
}

# Test function for validate_git_repo()
test_validate_git_repo_function() {
    # Test valid Git URLs
    assert_true validate_git_repo "https://github.com/user/repo.git" "GitHub HTTPS URL should be valid"
    assert_true validate_git_repo "git@github.com:user/repo.git" "GitHub SSH URL should be valid"
    assert_true validate_git_repo "https://gitlab.com/user/repo.git" "GitLab URL should be valid"

    # Test invalid Git URLs
    assert_false validate_git_repo "https://github.com/user/repo" "URL without .git should be invalid"
    assert_false validate_git_repo "http://github.com/user/repo.git" "HTTP URL should be invalid"
    assert_false validate_git_repo "ftp://example.com/repo.git" "FTP URL should be invalid"
    assert_false validate_git_repo "" "Empty URL should be invalid"
}

# Test function for validate_shell_identifier()
test_validate_shell_identifier_function() {
    # Test valid identifiers
    assert_true validate_shell_identifier "variable" "Simple variable name should be valid"
    assert_true validate_shell_identifier "my_var" "Variable with underscore should be valid"
    assert_true validate_shell_identifier "_private" "Variable starting with underscore should be valid"
    assert_true validate_shell_identifier "VAR123" "Variable with numbers should be valid"

    # Test invalid identifiers
    assert_false validate_shell_identifier "123var" "Variable starting with number should be invalid"
    assert_false validate_shell_identifier "my-var" "Variable with hyphen should be invalid"
    assert_false validate_shell_identifier "my var" "Variable with space should be invalid"
    assert_false validate_shell_identifier "" "Empty identifier should be invalid"

    # Test length limits
    local long_identifier="$(printf '%*s' 100 | tr ' ' 'a')"
    assert_false validate_shell_identifier "$long_identifier" "Overly long identifier should be invalid"
}

# Test function for validate_numeric()
test_validate_numeric_function() {
    # Test valid numbers
    assert_true validate_numeric "42" "Integer should be valid"
    assert_true validate_numeric "3.14" "Decimal should be valid"
    assert_true validate_numeric "-5" "Negative number should be valid"
    assert_true validate_numeric "0" "Zero should be valid"

    # Test with ranges
    assert_true validate_numeric "50" "1" "100" "Number in range should be valid"
    assert_false validate_numeric "150" "1" "100" "Number above range should be invalid"
    assert_false validate_numeric "-5" "1" "100" "Number below range should be invalid"

    # Test invalid numbers
    assert_false validate_numeric "abc" "Non-numeric should be invalid"
    assert_false validate_numeric "12.34.56" "Multiple decimals should be invalid"
    assert_false validate_numeric "" "Empty string should be invalid"
}

# Test library metadata
test_library_metadata() {
    assert_equals "1.0.0" "$LIB_VALIDATION_VERSION" "Library version should be set"
    assert_equals "1" "$LIB_VALIDATION_LOADED" "Library loaded flag should be set"
    assert_equals "1" "$__LIB_VALIDATION_LOADED" "Library guard should be set"
}

# Test edge cases and boundary conditions
test_edge_cases() {
    # Test with very long inputs
    local very_long_string="$(printf '%*s' 10000 | tr ' ' 'a')"

    # Most validation functions should handle long inputs gracefully
    assert_false validate_email "$very_long_string@example.com" "Very long email should be invalid"
    assert_false validate_hostname "$very_long_string.com" "Very long hostname should be invalid"

    # Test with control characters
    local string_with_ctrl=$'test\x00\x01\x02string'
    assert_false is_safe_string "$string_with_ctrl" "String with control chars should be unsafe"

    # Test sanitize_filename with control characters
    local sanitized
    sanitized="$(sanitize_filename "$string_with_ctrl")"
    assert_true test -n "$sanitized" "Sanitize should produce output for control chars"
    assert_false echo "$sanitized" | grep -q $'\x00' "Sanitized should not contain null bytes"
}

# Main test runner
main() {
    echo "Testing lib/validation.sh..."

    run_tests \
        test_validate_email_function \
        test_validate_url_function \
        test_validate_path_function \
        test_validate_hostname_function \
        test_validate_port_function \
        test_validate_ip_function \
        test_sanitize_filename_function \
        test_is_safe_string_function \
        test_validate_version_function \
        test_validate_git_repo_function \
        test_validate_shell_identifier_function \
        test_validate_numeric_function \
        test_library_metadata \
        test_edge_cases
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi