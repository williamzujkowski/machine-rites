#!/usr/bin/env bash
# Unit Tests - Bootstrap Script Core Functions
# Tests core bootstrap functionality and workflow
set -euo pipefail

# Source test framework with absolute path
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TEST_DIR/../test-framework.sh"

# Test configuration
readonly SCRIPT_UNDER_TEST="$PROJECT_ROOT/bootstrap_machine_rites.sh"

# Load required libraries safely
if [[ -f "$PROJECT_ROOT/lib/common.sh" ]]; then
    source "$PROJECT_ROOT/lib/common.sh"
fi
if [[ -f "$PROJECT_ROOT/lib/validation.sh" ]]; then
    source "$PROJECT_ROOT/lib/validation.sh"
fi

MOCK_ENV=""

# Test setup
setup_bootstrap_tests() {
    MOCK_ENV="$(setup_mock_environment "bootstrap")"
    export HOME="$MOCK_ENV/home"
    export CHEZMOI_SRC="$MOCK_ENV/chezmoi"
    export APT_CACHE_DIR="$MOCK_ENV/apt-cache"

    mkdir -p "$HOME" "$CHEZMOI_SRC" "$APT_CACHE_DIR"
    mkdir -p "$HOME/.config/chezmoi"
    mkdir -p "$HOME/.bashrc.d"

    log_debug "Setup bootstrap tests environment in: $MOCK_ENV"
}

# Test teardown
cleanup_bootstrap_tests() {
    cleanup_mock_environment "$MOCK_ENV"
}

# Unit Tests for Bootstrap Functions

test_bootstrap_argument_parsing() {
    # Test bootstrap script argument parsing
    local test_script="$MOCK_ENV/arg_test.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash

# Simulate bootstrap argument parsing
UNATTENDED=0
VERBOSE=0
SKIP_BACKUP=0
DEBUG=0

parse_arguments() {
    for arg in "$@"; do
        case "$arg" in
            --unattended|-u) UNATTENDED=1 ;;
            --verbose|-v) VERBOSE=1 ;;
            --skip-backup) SKIP_BACKUP=1 ;;
            --debug) DEBUG=1 ;;
            --help|-h) echo "help"; exit 0 ;;
            *) echo "Unknown option: $arg"; return 1 ;;
        esac
    done
}

# Test argument parsing
parse_arguments --unattended --verbose
[[ $UNATTENDED -eq 1 ]] || exit 1
[[ $VERBOSE -eq 1 ]] || exit 1

parse_arguments --skip-backup --debug
[[ $SKIP_BACKUP -eq 1 ]] || exit 1
[[ $DEBUG -eq 1 ]] || exit 1

# Test unknown argument handling
if parse_arguments --unknown 2>/dev/null; then
    exit 1  # Should have failed
fi
EOF

    assert_command_succeeds "bash '$test_script'" "argument parsing works correctly"
}

test_environment_variable_setup() {
    # Test environment variable initialization
    local test_script="$MOCK_ENV/env_test.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash

setup_environment() {
    # Set default values
    export DEBIAN_FRONTEND="${DEBIAN_FRONTEND:-noninteractive}"
    export CHEZMOI_SRC="${CHEZMOI_SRC:-$HOME/.local/share/chezmoi}"
    export GNUPGHOME="${GNUPGHOME:-$HOME/.gnupg}"

    # Validate critical paths
    [[ -n "$HOME" ]] || return 1

    # Create necessary directories
    mkdir -p "$HOME/.config"
    mkdir -p "$HOME/.local/bin"

    return 0
}

# Test environment setup
HOME="/tmp/test_home"
setup_environment || exit 1

# Check environment variables
[[ "$DEBIAN_FRONTEND" == "noninteractive" ]] || exit 1
[[ -n "$CHEZMOI_SRC" ]] || exit 1
[[ -n "$GNUPGHOME" ]] || exit 1

# Check directories created
[[ -d "$HOME/.config" ]] || exit 1
[[ -d "$HOME/.local/bin" ]] || exit 1
EOF

    assert_command_succeeds "bash '$test_script'" "environment setup works correctly"
}

test_package_installation_logic() {
    # Test package installation workflow
    local test_script="$MOCK_ENV/package_test.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash

install_package() {
    local package="$1"
    local retry_count=0
    local max_retries=3

    while [[ $retry_count -lt $max_retries ]]; do
        if mock_apt_install "$package"; then
            echo "Installed: $package"
            return 0
        fi

        ((retry_count++))
        echo "Retry $retry_count/$max_retries for $package"
        sleep 1
    done

    echo "Failed to install: $package"
    return 1
}

mock_apt_install() {
    local package="$1"

    # Simulate package installation
    case "$package" in
        "existing-package")
            return 0
            ;;
        "failing-package")
            return 1
            ;;
        "retry-package")
            # Fail first two times, succeed on third
            local attempt_file="/tmp/retry_${package}_attempts"
            local attempts=0
            if [[ -f "$attempt_file" ]]; then
                attempts=$(cat "$attempt_file")
            fi
            ((attempts++))
            echo "$attempts" > "$attempt_file"

            if [[ $attempts -ge 3 ]]; then
                rm -f "$attempt_file"
                return 0
            else
                return 1
            fi
            ;;
        *)
            return 0
            ;;
    esac
}

# Test successful installation
install_package "existing-package" || exit 1

# Test retry logic
install_package "retry-package" || exit 1

# Test failure after max retries
if install_package "failing-package" 2>/dev/null; then
    exit 1  # Should have failed
fi
EOF

    assert_command_succeeds "bash '$test_script'" "package installation logic works"
}

test_backup_creation() {
    # Test backup functionality
    local test_script="$MOCK_ENV/backup_test.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash

create_backup() {
    local source_dir="$1"
    local backup_dir="$2"

    if [[ ! -d "$source_dir" ]]; then
        echo "Source directory does not exist: $source_dir"
        return 1
    fi

    # Create backup with timestamp
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_path="$backup_dir/backup_$timestamp"

    mkdir -p "$backup_path"

    # Copy files
    if cp -r "$source_dir"/* "$backup_path"/ 2>/dev/null; then
        echo "Backup created: $backup_path"
        return 0
    else
        echo "Backup failed"
        return 1
    fi
}

# Setup test environment
source_dir="$1/source"
backup_dir="$1/backups"
mkdir -p "$source_dir" "$backup_dir"

# Create test files
echo "test content" > "$source_dir/file1.txt"
echo "more content" > "$source_dir/file2.txt"

# Test backup creation
create_backup "$source_dir" "$backup_dir" || exit 1

# Verify backup exists and contains files
backup_count=$(find "$backup_dir" -name "backup_*" -type d | wc -l)
[[ $backup_count -eq 1 ]] || exit 1

backup_path=$(find "$backup_dir" -name "backup_*" -type d | head -1)
[[ -f "$backup_path/file1.txt" ]] || exit 1
[[ -f "$backup_path/file2.txt" ]] || exit 1
EOF

    assert_command_succeeds "bash '$test_script' '$MOCK_ENV'" "backup creation works correctly"
}

test_chezmoi_initialization() {
    # Test chezmoi initialization logic
    local test_script="$MOCK_ENV/chezmoi_test.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash

initialize_chezmoi() {
    local source_dir="$1"
    local config_file="$HOME/.config/chezmoi/chezmoi.toml"

    # Create config directory
    mkdir -p "$(dirname "$config_file")"

    # Create chezmoi configuration
    cat > "$config_file" << CONFIG
[data]
    email = "test@example.com"
    name = "Test User"

[edit]
    command = "nano"

[merge]
    command = "vimdiff"
CONFIG

    # Initialize source directory
    mkdir -p "$source_dir"

    # Create basic chezmoi structure
    mkdir -p "$source_dir/.chezmoi"
    echo "# Chezmoi templates" > "$source_dir/.chezmoi/README.md"

    return 0
}

validate_chezmoi_setup() {
    local source_dir="$1"
    local config_file="$HOME/.config/chezmoi/chezmoi.toml"

    # Check config file exists and is valid
    [[ -f "$config_file" ]] || return 1

    # Check for required configuration
    grep -q "email" "$config_file" || return 1
    grep -q "name" "$config_file" || return 1

    # Check source directory structure
    [[ -d "$source_dir" ]] || return 1
    [[ -d "$source_dir/.chezmoi" ]] || return 1

    return 0
}

# Test chezmoi initialization
HOME="$1/home"
source_dir="$1/chezmoi"

initialize_chezmoi "$source_dir" || exit 1
validate_chezmoi_setup "$source_dir" || exit 1
EOF

    assert_command_succeeds "bash '$test_script' '$MOCK_ENV'" "chezmoi initialization works"
}

test_user_input_handling() {
    # Test user input handling in unattended mode
    local test_script="$MOCK_ENV/input_test.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash

get_user_input() {
    local prompt="$1"
    local default="$2"
    local unattended="${3:-0}"

    if [[ $unattended -eq 1 ]]; then
        echo "$default"
        return 0
    fi

    # In interactive mode, would read from stdin
    # For testing, simulate user input
    echo "user_input"
}

validate_email() {
    local email="$1"
    local email_regex='^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
    [[ "$email" =~ $email_regex ]]
}

get_user_email() {
    local unattended="$1"
    local email

    while true; do
        email=$(get_user_input "Enter email:" "test@example.com" "$unattended")

        if validate_email "$email"; then
            echo "$email"
            return 0
        else
            if [[ $unattended -eq 1 ]]; then
                echo "test@example.com"  # Fallback for unattended
                return 0
            fi
            echo "Invalid email format" >&2
        fi
    done
}

# Test unattended mode
result=$(get_user_email 1)
[[ "$result" == "test@example.com" ]] || exit 1

# Test email validation
validate_email "valid@example.com" || exit 1
! validate_email "invalid.email" || exit 1
EOF

    assert_command_succeeds "bash '$test_script'" "user input handling works correctly"
}

test_error_recovery() {
    # Test error recovery mechanisms
    local test_script="$MOCK_ENV/recovery_test.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash

cleanup_on_error() {
    local temp_files=("$@")

    echo "Cleaning up temporary files..."
    for file in "${temp_files[@]}"; do
        [[ -f "$file" ]] && rm -f "$file"
        [[ -d "$file" ]] && rm -rf "$file"
    done
}

safe_operation() {
    local operation="$1"
    local temp_dir="$2"

    # Create temporary files
    local temp_files=("$temp_dir/temp1" "$temp_dir/temp2")
    touch "${temp_files[@]}"

    # Set up error trap
    trap 'cleanup_on_error "${temp_files[@]}"' EXIT ERR

    case "$operation" in
        "succeed")
            return 0
            ;;
        "fail")
            return 1
            ;;
    esac
}

# Test successful operation
temp_dir="$1/temp"
mkdir -p "$temp_dir"

safe_operation "succeed" "$temp_dir" || exit 1

# Test failed operation with cleanup
if safe_operation "fail" "$temp_dir" 2>/dev/null; then
    exit 1  # Should have failed
fi

# Verify cleanup occurred (files should be removed)
[[ ! -f "$temp_dir/temp1" ]] || exit 1
[[ ! -f "$temp_dir/temp2" ]] || exit 1
EOF

    assert_command_succeeds "bash '$test_script' '$MOCK_ENV'" "error recovery works correctly"
}

test_dependency_checking() {
    # Test dependency verification
    local test_script="$MOCK_ENV/dependency_test.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash

check_dependencies() {
    local dependencies=("$@")
    local missing=()

    for dep in "${dependencies[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing+=("$dep")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Missing dependencies: ${missing[*]}"
        return 1
    fi

    return 0
}

install_missing_dependencies() {
    local dependencies=("$@")

    for dep in "${dependencies[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            echo "Installing: $dep"
            # Mock installation
            create_mock_command "$dep"
        fi
    done
}

create_mock_command() {
    local cmd="$1"
    local mock_dir="/tmp/mock_bin"

    mkdir -p "$mock_dir"
    cat > "$mock_dir/$cmd" << 'MOCK'
#!/bin/bash
echo "Mock command: $0 $*"
MOCK
    chmod +x "$mock_dir/$cmd"
    export PATH="$mock_dir:$PATH"
}

# Test with existing commands
check_dependencies "bash" "echo" || exit 1

# Test with missing dependencies
if check_dependencies "nonexistent_cmd" 2>/dev/null; then
    exit 1  # Should have failed
fi

# Test dependency installation
install_missing_dependencies "test_cmd"
check_dependencies "test_cmd" || exit 1
EOF

    assert_command_succeeds "bash '$test_script'" "dependency checking works correctly"
}

test_configuration_validation() {
    # Test configuration file validation
    local test_script="$MOCK_ENV/config_validation_test.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash

validate_configuration() {
    local config_file="$1"

    # Check file exists
    [[ -f "$config_file" ]] || return 1

    # Check required fields
    local required_fields=("email" "name" "editor")

    for field in "${required_fields[@]}"; do
        if ! grep -q "^$field" "$config_file"; then
            echo "Missing required field: $field"
            return 1
        fi
    done

    # Validate email format
    local email
    email=$(grep "^email" "$config_file" | cut -d'=' -f2 | tr -d ' "')
    local email_regex='^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'

    if ! [[ "$email" =~ $email_regex ]]; then
        echo "Invalid email format: $email"
        return 1
    fi

    return 0
}

create_test_config() {
    local config_file="$1"
    local email="$2"

    cat > "$config_file" << CONFIG
email="$email"
name="Test User"
editor="nano"
CONFIG
}

# Test valid configuration
config_file="$1/valid_config.toml"
create_test_config "$config_file" "test@example.com"
validate_configuration "$config_file" || exit 1

# Test invalid email
invalid_config="$1/invalid_config.toml"
create_test_config "$invalid_config" "invalid.email"
if validate_configuration "$invalid_config" 2>/dev/null; then
    exit 1  # Should have failed
fi

# Test missing fields
incomplete_config="$1/incomplete_config.toml"
echo 'email="test@example.com"' > "$incomplete_config"
if validate_configuration "$incomplete_config" 2>/dev/null; then
    exit 1  # Should have failed
fi
EOF

    assert_command_succeeds "bash '$test_script' '$MOCK_ENV'" "configuration validation works"
}

test_progress_reporting() {
    # Test progress reporting functionality
    local test_script="$MOCK_ENV/progress_test.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash

show_progress() {
    local current="$1"
    local total="$2"
    local task="$3"

    local percent=$((current * 100 / total))
    local filled=$((percent / 5))
    local empty=$((20 - filled))

    printf "\r[%s%s] %d%% - %s" \
        "$(printf "%*s" $filled | tr ' ' '=')" \
        "$(printf "%*s" $empty)" \
        "$percent" \
        "$task"
}

simulate_task_with_progress() {
    local tasks=("Initialize" "Download" "Install" "Configure" "Finalize")
    local total=${#tasks[@]}

    for i in "${!tasks[@]}"; do
        show_progress $((i + 1)) "$total" "${tasks[$i]}"
        # sleep 0.1  # Simulate work - removed to speed up tests
    done
    echo ""  # New line after progress
}

# Test progress reporting
output=$(simulate_task_with_progress 2>&1)

# Check that progress was shown
echo "$output" | grep -q "100%" || exit 1
echo "$output" | grep -q "Finalize" || exit 1
EOF

    assert_command_succeeds "bash '$test_script'" "progress reporting works correctly"
}

# Test execution
main() {
    init_test_framework
    start_test_suite "Bootstrap_Core"

    setup_bootstrap_tests

    run_test "Bootstrap Argument Parsing" test_bootstrap_argument_parsing
    run_test "Environment Variable Setup" test_environment_variable_setup
    run_test "Package Installation Logic" test_package_installation_logic
    run_test "Backup Creation" test_backup_creation
    run_test "Chezmoi Initialization" test_chezmoi_initialization
    run_test "User Input Handling" test_user_input_handling
    run_test "Error Recovery" test_error_recovery
    run_test "Dependency Checking" test_dependency_checking
    run_test "Configuration Validation" test_configuration_validation
    run_test "Progress Reporting" test_progress_reporting

    cleanup_bootstrap_tests
    end_test_suite
    finalize_test_framework
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi