#!/usr/bin/env bash
# Unit Tests - Input Validation and Sanitization
# Tests validation functions and input sanitization
set -euo pipefail

# Source test framework
source "$(dirname "${BASH_SOURCE[0]}")/../test-framework.sh"

# Test configuration
readonly SCRIPT_UNDER_TEST="$PROJECT_ROOT/bootstrap_machine_rites.sh"
readonly MOCK_ENV="$(setup_mock_environment "validation")"

# Test setup
setup_validation_tests() {
    export HOME="$MOCK_ENV/home"
    mkdir -p "$HOME"
    log_debug "Setup validation tests environment in: $MOCK_ENV"
}

# Test teardown
cleanup_validation_tests() {
    cleanup_mock_environment "$MOCK_ENV"
}

# Unit Tests for Validation Functions

test_path_validation() {
    # Test path validation and sanitization
    local test_script="$MOCK_ENV/path_test.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash

validate_path() {
    local path="$1"

    # Check for path traversal attempts
    if [[ "$path" == *".."* ]]; then
        return 1
    fi

    # Check for absolute path requirement
    if [[ "$path" != /* ]]; then
        return 1
    fi

    # Check for null bytes
    if [[ "$path" == *$'\0'* ]]; then
        return 1
    fi

    return 0
}

# Test cases
validate_path "/home/user/valid/path" || exit 1
! validate_path "../../etc/passwd" || exit 1
! validate_path "relative/path" || exit 1
! validate_path "/path/with$(printf '\0')nullbyte" || exit 1
EOF

    assert_command_succeeds "bash '$test_script'" "path validation works correctly"
}

test_email_validation() {
    # Test email address validation
    local test_script="$MOCK_ENV/email_test.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash

validate_email() {
    local email="$1"
    local email_regex='^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'

    if [[ "$email" =~ $email_regex ]]; then
        return 0
    else
        return 1
    fi
}

# Test valid emails
validate_email "user@example.com" || exit 1
validate_email "test.email+tag@domain.co.uk" || exit 1
validate_email "user123@test-domain.org" || exit 1

# Test invalid emails
! validate_email "invalid.email" || exit 1
! validate_email "@example.com" || exit 1
! validate_email "user@" || exit 1
! validate_email "user@.com" || exit 1
! validate_email "user space@example.com" || exit 1
EOF

    assert_command_succeeds "bash '$test_script'" "email validation works correctly"
}

test_command_injection_prevention() {
    # Test prevention of command injection
    local test_script="$MOCK_ENV/injection_test.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash

safe_execute() {
    local cmd="$1"

    # Check for dangerous characters
    if [[ "$cmd" == *";"* ]] || [[ "$cmd" == *"|"* ]] || [[ "$cmd" == *"&"* ]] ||
       [[ "$cmd" == *"$("* ]] || [[ "$cmd" == *"`"* ]] || [[ "$cmd" == *">"* ]] ||
       [[ "$cmd" == *"<"* ]]; then
        echo "DANGEROUS_COMMAND"
        return 1
    fi

    return 0
}

# Test safe commands
safe_execute "ls -la" || exit 1
safe_execute "echo hello" || exit 1

# Test dangerous commands
! safe_execute "ls; rm -rf /" || exit 1
! safe_execute "ls | grep test" || exit 1
! safe_execute "echo \$(rm file)" || exit 1
! safe_execute "ls > /dev/null" || exit 1
EOF

    assert_command_succeeds "bash '$test_script'" "command injection prevention works"
}

test_filename_sanitization() {
    # Test filename sanitization
    local test_script="$MOCK_ENV/filename_test.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash

sanitize_filename() {
    local filename="$1"

    # Remove dangerous characters
    filename="${filename//[^a-zA-Z0-9._-]/_}"

    # Limit length
    if [[ ${#filename} -gt 255 ]]; then
        filename="${filename:0:255}"
    fi

    # Ensure not empty
    if [[ -z "$filename" ]]; then
        filename="default"
    fi

    echo "$filename"
}

# Test sanitization
result=$(sanitize_filename "normal_file.txt")
[[ "$result" == "normal_file.txt" ]] || exit 1

result=$(sanitize_filename "file with spaces.txt")
[[ "$result" == "file_with_spaces.txt" ]] || exit 1

result=$(sanitize_filename "dangerous/file\\name")
[[ "$result" == "dangerous_file_name" ]] || exit 1

result=$(sanitize_filename "")
[[ "$result" == "default" ]] || exit 1
EOF

    assert_command_succeeds "bash '$test_script'" "filename sanitization works correctly"
}

test_input_length_validation() {
    # Test input length validation
    local test_script="$MOCK_ENV/length_test.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash

validate_input_length() {
    local input="$1"
    local max_length="${2:-1000}"

    if [[ ${#input} -gt $max_length ]]; then
        return 1
    fi

    return 0
}

# Test normal length
validate_input_length "normal string" 100 || exit 1

# Test too long
long_string=$(printf 'a%.0s' {1..2000})
! validate_input_length "$long_string" 1000 || exit 1

# Test edge case
edge_string=$(printf 'a%.0s' {1..100})
validate_input_length "$edge_string" 100 || exit 1
EOF

    assert_command_succeeds "bash '$test_script'" "input length validation works correctly"
}

test_numeric_validation() {
    # Test numeric input validation
    local test_script="$MOCK_ENV/numeric_test.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash

validate_numeric() {
    local input="$1"
    local min="${2:-0}"
    local max="${3:-999999}"

    # Check if numeric
    if ! [[ "$input" =~ ^[0-9]+$ ]]; then
        return 1
    fi

    # Check range
    if [[ $input -lt $min ]] || [[ $input -gt $max ]]; then
        return 1
    fi

    return 0
}

# Test valid numbers
validate_numeric "123" 0 1000 || exit 1
validate_numeric "0" 0 100 || exit 1
validate_numeric "999" 0 1000 || exit 1

# Test invalid numbers
! validate_numeric "abc" 0 100 || exit 1
! validate_numeric "12.5" 0 100 || exit 1
! validate_numeric "-5" 0 100 || exit 1
! validate_numeric "1001" 0 1000 || exit 1
EOF

    assert_command_succeeds "bash '$test_script'" "numeric validation works correctly"
}

test_url_validation() {
    # Test URL validation
    local test_script="$MOCK_ENV/url_test.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash

validate_url() {
    local url="$1"
    local url_regex='^https?://[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}(/.*)?$'

    if [[ "$url" =~ $url_regex ]]; then
        return 0
    else
        return 1
    fi
}

# Test valid URLs
validate_url "https://example.com" || exit 1
validate_url "http://test.org/path" || exit 1
validate_url "https://sub.domain.com/path/to/file" || exit 1

# Test invalid URLs
! validate_url "ftp://example.com" || exit 1
! validate_url "https://" || exit 1
! validate_url "not-a-url" || exit 1
! validate_url "javascript:alert(1)" || exit 1
EOF

    assert_command_succeeds "bash '$test_script'" "URL validation works correctly"
}

test_version_string_validation() {
    # Test version string validation
    local test_script="$MOCK_ENV/version_test.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash

validate_version() {
    local version="$1"
    local version_regex='^[0-9]+\.[0-9]+(\.[0-9]+)?(-[a-zA-Z0-9]+)?$'

    if [[ "$version" =~ $version_regex ]]; then
        return 0
    else
        return 1
    fi
}

# Test valid versions
validate_version "1.0.0" || exit 1
validate_version "2.5" || exit 1
validate_version "1.0.0-beta" || exit 1
validate_version "10.15.3-alpha1" || exit 1

# Test invalid versions
! validate_version "1" || exit 1
! validate_version "v1.0.0" || exit 1
! validate_version "1.0.0.0" || exit 1
! validate_version "1.0-" || exit 1
EOF

    assert_command_succeeds "bash '$test_script'" "version validation works correctly"
}

test_special_character_handling() {
    # Test handling of special characters
    local test_script="$MOCK_ENV/special_char_test.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash

escape_special_chars() {
    local input="$1"

    # Escape shell metacharacters
    input="${input//\$/\\$}"
    input="${input//\`/\\`}"
    input="${input//\"/\\\"}"
    input="${input//\'/\\\'}"
    input="${input//\;/\\;}"

    echo "$input"
}

# Test escaping
result=$(escape_special_chars 'test$variable')
[[ "$result" == 'test\$variable' ]] || exit 1

result=$(escape_special_chars 'command`injection`')
[[ "$result" == 'command\`injection\`' ]] || exit 1

result=$(escape_special_chars 'quote"test')
[[ "$result" == 'quote\"test' ]] || exit 1
EOF

    assert_command_succeeds "bash '$test_script'" "special character handling works correctly"
}

test_configuration_validation() {
    # Test configuration file validation
    local test_config="$MOCK_ENV/test.conf"
    cat > "$test_config" << 'EOF'
# Valid configuration
USER_NAME=testuser
EMAIL=test@example.com
DEBUG=true
MAX_RETRIES=3
EOF

    local test_script="$MOCK_ENV/config_test.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash

validate_config() {
    local config_file="$1"

    # Check file exists and is readable
    [[ -f "$config_file" ]] && [[ -r "$config_file" ]] || return 1

    # Check for dangerous patterns
    if grep -E '(rm|sudo|eval|exec|system)' "$config_file" >/dev/null 2>&1; then
        return 1
    fi

    # Validate format
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue

        # Validate key format
        if ! [[ "$key" =~ ^[A-Z_][A-Z0-9_]*$ ]]; then
            return 1
        fi

        # Validate value (no dangerous content)
        if [[ "$value" == *"$("* ]] || [[ "$value" == *"`"* ]]; then
            return 1
        fi
    done < "$config_file"

    return 0
}

validate_config "$1"
EOF

    assert_command_succeeds "bash '$test_script' '$test_config'" "configuration validation works correctly"
}

# Test execution
main() {
    init_test_framework
    start_test_suite "Input_Validation"

    setup_validation_tests

    run_test "Path Validation" test_path_validation
    run_test "Email Validation" test_email_validation
    run_test "Command Injection Prevention" test_command_injection_prevention
    run_test "Filename Sanitization" test_filename_sanitization
    run_test "Input Length Validation" test_input_length_validation
    run_test "Numeric Validation" test_numeric_validation
    run_test "URL Validation" test_url_validation
    run_test "Version String Validation" test_version_string_validation
    run_test "Special Character Handling" test_special_character_handling
    run_test "Configuration Validation" test_configuration_validation

    cleanup_validation_tests
    end_test_suite
    finalize_test_framework
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi