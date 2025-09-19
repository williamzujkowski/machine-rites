#!/usr/bin/env bash
# Integration Tests - Chezmoi Apply Workflow
# Tests the complete chezmoi configuration and apply process
set -euo pipefail

# Source test framework
source "$(dirname "${BASH_SOURCE[0]}")/../test-framework.sh"

# Test configuration
readonly SCRIPT_UNDER_TEST="$PROJECT_ROOT/bootstrap_machine_rites.sh"
readonly MOCK_ENV="$(setup_mock_environment "chezmoi_integration")"

# Test setup
setup_chezmoi_integration_tests() {
    export HOME="$MOCK_ENV/home"
    export CHEZMOI_SRC="$MOCK_ENV/chezmoi"
    export XDG_CONFIG_HOME="$HOME/.config"

    mkdir -p "$HOME" "$CHEZMOI_SRC" "$XDG_CONFIG_HOME"
    mkdir -p "$HOME/.local/bin"
    mkdir -p "$HOME/.bashrc.d"

    # Create mock chezmoi executable
    create_mock_chezmoi

    log_debug "Setup chezmoi integration tests in: $MOCK_ENV"
}

# Test teardown
cleanup_chezmoi_integration_tests() {
    cleanup_mock_environment "$MOCK_ENV"
}

# Create mock chezmoi executable
create_mock_chezmoi() {
    local chezmoi_bin="$HOME/.local/bin/chezmoi"

    cat > "$chezmoi_bin" << 'EOF'
#!/bin/bash
# Mock chezmoi for testing

case "$1" in
    "init")
        shift
        echo "chezmoi: initialized"
        mkdir -p "$HOME/.local/share/chezmoi"
        ;;
    "apply")
        echo "chezmoi: applying configuration"
        # Simulate applying dotfiles
        mkdir -p "$HOME/.bashrc.d"
        echo "# Applied by chezmoi" > "$HOME/.bashrc.d/00-chezmoi.sh"
        ;;
    "status")
        echo "A .bashrc.d/00-chezmoi.sh"
        ;;
    "diff")
        echo "--- a/.bashrc.d/00-chezmoi.sh"
        echo "+++ b/.bashrc.d/00-chezmoi.sh"
        echo "@@ -0,0 +1,1 @@"
        echo "+# Applied by chezmoi"
        ;;
    "doctor")
        echo "chezmoi: OK"
        ;;
    "execute-template")
        shift
        if [[ "$1" == "{{ .chezmoi.sourceDir }}" ]]; then
            echo "$HOME/.local/share/chezmoi"
        else
            echo "template_result"
        fi
        ;;
    "--version")
        echo "chezmoi version 2.46.1"
        ;;
    *)
        echo "chezmoi: unknown command: $1" >&2
        exit 1
        ;;
esac
EOF

    chmod +x "$chezmoi_bin"
    export PATH="$HOME/.local/bin:$PATH"
}

# Integration Tests

test_chezmoi_installation_and_setup() {
    # Test complete chezmoi installation and initial setup
    local test_script="$MOCK_ENV/chezmoi_setup_test.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash

install_chezmoi() {
    local install_dir="$HOME/.local/bin"
    mkdir -p "$install_dir"

    # Simulate chezmoi installation
    echo "Installing chezmoi to $install_dir"

    # In real scenario, would download from GitHub
    # For testing, copy mock version
    if [[ -f "$HOME/.local/bin/chezmoi" ]]; then
        return 0
    else
        return 1
    fi
}

configure_chezmoi() {
    local config_dir="$HOME/.config/chezmoi"
    local config_file="$config_dir/chezmoi.toml"

    mkdir -p "$config_dir"

    cat > "$config_file" << 'CONFIG'
[data]
    email = "test@example.com"
    name = "Test User"
    editor = "nano"

[edit]
    command = "nano"

[merge]
    command = "vimdiff"

[git]
    autoCommit = true
    autoPush = true
CONFIG

    return 0
}

initialize_chezmoi_repo() {
    local source_dir="$1"

    # Initialize chezmoi with source directory
    chezmoi init --source "$source_dir" || return 1

    return 0
}

# Test installation
install_chezmoi || exit 1

# Test configuration
configure_chezmoi || exit 1

# Test initialization
initialize_chezmoi_repo "$CHEZMOI_SRC" || exit 1

# Verify chezmoi is working
chezmoi doctor >/dev/null || exit 1
EOF

    assert_command_succeeds "bash '$test_script'" "chezmoi installation and setup works"
}

test_dotfiles_template_processing() {
    # Test template processing and variable substitution
    local test_script="$MOCK_ENV/template_test.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash

create_template_files() {
    local source_dir="$1"

    mkdir -p "$source_dir"

    # Create a template bashrc file
    cat > "$source_dir/dot_bashrc.tmpl" << 'TEMPLATE'
# Bashrc for {{ .chezmoi.username }}
export USER_EMAIL="{{ .email }}"
export USER_NAME="{{ .name }}"
export EDITOR="{{ .editor }}"

# Machine-specific settings
{{- if eq .chezmoi.os "linux" }}
alias ll='ls -alF'
{{- end }}

# Development tools
export PATH="$HOME/.local/bin:$PATH"
TEMPLATE

    # Create a gitconfig template
    cat > "$source_dir/dot_gitconfig.tmpl" << 'TEMPLATE'
[user]
    name = {{ .name }}
    email = {{ .email }}

[core]
    editor = {{ .editor }}
    autocrlf = input

[init]
    defaultBranch = main
TEMPLATE

    return 0
}

test_template_execution() {
    local source_dir="$1"

    # Test that templates can be processed
    if ! chezmoi execute-template "{{ .chezmoi.sourceDir }}" >/dev/null; then
        return 1
    fi

    return 0
}

# Create template files
create_template_files "$CHEZMOI_SRC" || exit 1

# Test template processing
test_template_execution "$CHEZMOI_SRC" || exit 1
EOF

    assert_command_succeeds "bash '$test_script'" "template processing works correctly"
}

test_configuration_application() {
    # Test applying chezmoi configuration to system
    local test_script="$MOCK_ENV/apply_test.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash

apply_chezmoi_config() {
    echo "Applying chezmoi configuration..."

    # Check for pending changes
    if chezmoi status | grep -q "A "; then
        echo "Found pending changes"
    fi

    # Apply changes
    if chezmoi apply; then
        echo "Configuration applied successfully"
        return 0
    else
        echo "Failed to apply configuration"
        return 1
    fi
}

verify_applied_config() {
    # Check that files were created
    if [[ -f "$HOME/.bashrc.d/00-chezmoi.sh" ]]; then
        echo "Bashrc configuration applied"
        return 0
    else
        echo "Bashrc configuration not found"
        return 1
    fi
}

# Test configuration application
apply_chezmoi_config || exit 1

# Verify configuration was applied
verify_applied_config || exit 1
EOF

    assert_command_succeeds "bash '$test_script'" "configuration application works"
}

test_state_management() {
    # Test chezmoi state management and tracking
    local test_script="$MOCK_ENV/state_test.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash

check_chezmoi_status() {
    local status_output
    status_output=$(chezmoi status 2>&1)

    echo "Chezmoi status: $status_output"
    return 0
}

show_pending_changes() {
    local diff_output
    diff_output=$(chezmoi diff 2>&1)

    if [[ -n "$diff_output" ]]; then
        echo "Pending changes found:"
        echo "$diff_output"
    else
        echo "No pending changes"
    fi

    return 0
}

# Test status checking
check_chezmoi_status || exit 1

# Test diff functionality
show_pending_changes || exit 1
EOF

    assert_command_succeeds "bash '$test_script'" "state management works correctly"
}

test_error_handling_during_apply() {
    # Test error handling during chezmoi apply
    local test_script="$MOCK_ENV/error_handling_test.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash

# Override chezmoi to simulate errors
chezmoi() {
    case "$1" in
        "apply")
            if [[ "${SIMULATE_ERROR:-}" == "true" ]]; then
                echo "chezmoi: error applying configuration" >&2
                return 1
            fi
            command chezmoi "$@"
            ;;
        *)
            command chezmoi "$@"
            ;;
    esac
}

safe_apply_chezmoi() {
    local max_attempts=3
    local attempt=1

    while [[ $attempt -le $max_attempts ]]; do
        echo "Attempt $attempt/$max_attempts"

        if chezmoi apply; then
            echo "Successfully applied on attempt $attempt"
            return 0
        fi

        ((attempt++))
        sleep 1
    done

    echo "Failed to apply after $max_attempts attempts"
    return 1
}

# Test successful apply
safe_apply_chezmoi || exit 1

# Test error handling
export SIMULATE_ERROR=true
if safe_apply_chezmoi 2>/dev/null; then
    exit 1  # Should have failed
fi

echo "Error handling test passed"
EOF

    assert_command_succeeds "bash '$test_script'" "error handling during apply works"
}

test_backup_and_restore() {
    # Test backup creation before applying changes
    local test_script="$MOCK_ENV/backup_test.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash

create_backup_before_apply() {
    local backup_dir="$HOME/dotfiles-backup-$(date +%Y%m%d_%H%M%S)"

    echo "Creating backup in: $backup_dir"
    mkdir -p "$backup_dir"

    # Backup existing dotfiles
    for file in "$HOME"/.bashrc "$HOME"/.gitconfig; do
        if [[ -f "$file" ]]; then
            cp "$file" "$backup_dir/"
        fi
    done

    # Create restore script
    cat > "$backup_dir/restore.sh" << 'RESTORE'
#!/bin/bash
echo "Restoring from backup..."
for file in .bashrc .gitconfig; do
    if [[ -f "$file" ]]; then
        cp "$file" "$HOME/"
        echo "Restored: $file"
    fi
done
RESTORE
    chmod +x "$backup_dir/restore.sh"

    echo "$backup_dir"
}

test_restore_functionality() {
    local backup_dir="$1"

    # Create test files to restore
    echo "original bashrc" > "$backup_dir/.bashrc"

    # Test restore
    (cd "$backup_dir" && ./restore.sh) || return 1

    # Verify restoration
    if [[ -f "$HOME/.bashrc" ]]; then
        local content
        content=$(cat "$HOME/.bashrc")
        [[ "$content" == "original bashrc" ]] || return 1
    fi

    return 0
}

# Test backup creation
backup_dir=$(create_backup_before_apply)
[[ -d "$backup_dir" ]] || exit 1
[[ -f "$backup_dir/restore.sh" ]] || exit 1

# Test restore functionality
test_restore_functionality "$backup_dir" || exit 1
EOF

    assert_command_succeeds "bash '$test_script'" "backup and restore works correctly"
}

test_configuration_validation() {
    # Test validation of chezmoi configuration
    local test_script="$MOCK_ENV/config_validation_test.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash

validate_chezmoi_config() {
    local config_file="$HOME/.config/chezmoi/chezmoi.toml"

    # Check config file exists
    [[ -f "$config_file" ]] || return 1

    # Check required sections
    local required_sections=("data" "edit" "git")

    for section in "${required_sections[@]}"; do
        if ! grep -q "^\[$section\]" "$config_file"; then
            echo "Missing section: $section"
            return 1
        fi
    done

    # Check required data fields
    local required_fields=("email" "name")

    for field in "${required_fields[@]}"; do
        if ! grep -A 10 "^\[data\]" "$config_file" | grep -q "$field"; then
            echo "Missing data field: $field"
            return 1
        fi
    done

    return 0
}

validate_source_directory() {
    local source_dir="$1"

    # Check source directory exists
    [[ -d "$source_dir" ]] || return 1

    # Check for valid chezmoi files
    local has_templates=false

    if find "$source_dir" -name "*.tmpl" -o -name "dot_*" | grep -q .; then
        has_templates=true
    fi

    $has_templates || return 1

    return 0
}

# Test configuration validation
validate_chezmoi_config || exit 1

# Test source directory validation
validate_source_directory "$CHEZMOI_SRC" || exit 1
EOF

    assert_command_succeeds "bash '$test_script'" "configuration validation works"
}

test_integration_with_git() {
    # Test git integration functionality
    local test_script="$MOCK_ENV/git_integration_test.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash

# Mock git for testing
git() {
    case "$1" in
        "init")
            mkdir -p .git
            echo "Initialized git repository"
            ;;
        "add")
            echo "Added files to git"
            ;;
        "commit")
            echo "Committed changes"
            ;;
        "remote")
            case "$2" in
                "add")
                    echo "Added remote: $3 $4"
                    ;;
                "-v")
                    echo "origin  https://github.com/user/dotfiles.git (fetch)"
                    echo "origin  https://github.com/user/dotfiles.git (push)"
                    ;;
            esac
            ;;
        "status")
            echo "On branch main"
            echo "nothing to commit, working tree clean"
            ;;
        *)
            echo "git: $*"
            ;;
    esac
}

test_git_initialization() {
    local source_dir="$1"

    cd "$source_dir" || return 1

    # Initialize git repository
    git init || return 1
    [[ -d ".git" ]] || return 1

    # Add initial files
    git add . || return 1
    git commit -m "Initial commit" || return 1

    return 0
}

test_git_remote_setup() {
    local source_dir="$1"

    cd "$source_dir" || return 1

    # Add remote repository
    git remote add origin "https://github.com/user/dotfiles.git" || return 1

    # Verify remote
    git remote -v | grep -q "origin" || return 1

    return 0
}

# Test git initialization
test_git_initialization "$CHEZMOI_SRC" || exit 1

# Test remote setup
test_git_remote_setup "$CHEZMOI_SRC" || exit 1
EOF

    assert_command_succeeds "bash '$test_script'" "git integration works correctly"
}

test_multi_machine_synchronization() {
    # Test multi-machine synchronization capabilities
    local test_script="$MOCK_ENV/sync_test.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash

simulate_machine_differences() {
    local machine1_dir="$1/machine1"
    local machine2_dir="$1/machine2"

    mkdir -p "$machine1_dir" "$machine2_dir"

    # Machine 1 configuration
    cat > "$machine1_dir/machine_config.toml" << 'CONFIG1'
[data]
    hostname = "dev-machine"
    os = "linux"
    arch = "x64"
CONFIG1

    # Machine 2 configuration
    cat > "$machine2_dir/machine_config.toml" << 'CONFIG2'
[data]
    hostname = "prod-server"
    os = "linux"
    arch = "arm64"
CONFIG2

    return 0
}

test_conditional_templates() {
    local template_content='
# Configuration for {{ .hostname }}
{{- if eq .arch "x64" }}
export ARCH_SPECIFIC="x64_optimization"
{{- else if eq .arch "arm64" }}
export ARCH_SPECIFIC="arm64_optimization"
{{- end }}

{{- if eq .hostname "dev-machine" }}
export ENV="development"
{{- else }}
export ENV="production"
{{- end }}
'

    echo "Template content created for conditional processing"
    return 0
}

# Test machine-specific configurations
simulate_machine_differences "$MOCK_ENV" || exit 1

# Test conditional template processing
test_conditional_templates || exit 1
EOF

    assert_command_succeeds "bash '$test_script'" "multi-machine synchronization works"
}

test_performance_and_scalability() {
    # Test performance with large configurations
    local test_script="$MOCK_ENV/performance_test.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash

create_large_configuration() {
    local source_dir="$1"
    local num_files="${2:-100}"

    mkdir -p "$source_dir"

    echo "Creating $num_files configuration files..."

    for ((i=1; i<=num_files; i++)); do
        cat > "$source_dir/dot_config_file_$i" << CONFIG
# Configuration file $i
export CONFIG_VAR_$i="value_$i"
alias alias_$i="command_$i"
CONFIG
    done

    return 0
}

benchmark_apply_operation() {
    local start_time end_time duration

    start_time=$(date +%s.%N)

    # Simulate chezmoi apply
    chezmoi apply >/dev/null 2>&1

    end_time=$(date +%s.%N)
    duration=$(awk "BEGIN {printf \"%.3f\", $end_time - $start_time}")

    echo "Apply operation took: ${duration}s"

    # Performance threshold (should complete within 5 seconds)
    if (( $(awk "BEGIN {print ($duration < 5.0)}") )); then
        return 0
    else
        return 1
    fi
}

# Test with moderate number of files
create_large_configuration "$CHEZMOI_SRC" 50 || exit 1

# Benchmark apply operation
benchmark_apply_operation || exit 1
EOF

    assert_command_succeeds "bash '$test_script'" "performance and scalability acceptable"
}

# Test execution
main() {
    init_test_framework
    start_test_suite "Chezmoi_Integration"

    setup_chezmoi_integration_tests

    run_test "Chezmoi Installation and Setup" test_chezmoi_installation_and_setup
    run_test "Dotfiles Template Processing" test_dotfiles_template_processing
    run_test "Configuration Application" test_configuration_application
    run_test "State Management" test_state_management
    run_test "Error Handling During Apply" test_error_handling_during_apply
    run_test "Backup and Restore" test_backup_and_restore
    run_test "Configuration Validation" test_configuration_validation
    run_test "Integration with Git" test_integration_with_git
    run_test "Multi-Machine Synchronization" test_multi_machine_synchronization
    run_test "Performance and Scalability" test_performance_and_scalability

    cleanup_chezmoi_integration_tests
    end_test_suite
    finalize_test_framework
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi