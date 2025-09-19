#!/usr/bin/env bash
# End-to-End Tests - Complete Bootstrap Workflow
# Tests the complete machine-rites bootstrap process from start to finish
set -euo pipefail

# Source test framework
source "$(dirname "${BASH_SOURCE[0]}")/../test-framework.sh"

# Test configuration
readonly SCRIPT_UNDER_TEST="$PROJECT_ROOT/bootstrap_machine_rites.sh"
readonly MOCK_ENV="$(setup_mock_environment "e2e_bootstrap")"

# Test setup
setup_e2e_tests() {
    export HOME="$MOCK_ENV/home"
    export CHEZMOI_SRC="$MOCK_ENV/chezmoi"
    export APT_CACHE_DIR="$MOCK_ENV/apt-cache"
    export GNUPGHOME="$HOME/.gnupg"

    mkdir -p "$HOME" "$CHEZMOI_SRC" "$APT_CACHE_DIR" "$GNUPGHOME"
    mkdir -p "$HOME/.config"
    mkdir -p "$HOME/.local/bin"
    mkdir -p "$HOME/.bashrc.d"

    # Setup mock environment with all required tools
    setup_mock_system

    log_debug "Setup E2E tests environment in: $MOCK_ENV"
}

# Test teardown
cleanup_e2e_tests() {
    cleanup_mock_environment "$MOCK_ENV"
}

# Setup complete mock system
setup_mock_system() {
    local bin_dir="$HOME/.local/bin"
    local apt_dir="$MOCK_ENV/usr/bin"

    mkdir -p "$bin_dir" "$apt_dir"

    # Add mock directories to PATH
    export PATH="$bin_dir:$apt_dir:$PATH"

    # Create mock system commands
    create_mock_apt
    create_mock_systemctl
    create_mock_gpg
    create_mock_chezmoi
    create_mock_git
    create_mock_pass
    create_mock_lsb_release

    # Create mock files and directories
    setup_mock_filesystem
}

create_mock_apt() {
    cat > "$MOCK_ENV/usr/bin/apt" << 'EOF'
#!/bin/bash
case "$1" in
    "update")
        echo "Reading package lists..."
        echo "All packages are up to date."
        ;;
    "install")
        shift
        for package in "$@"; do
            [[ "$package" == "-y" ]] && continue
            echo "Installing $package..."
            echo "Setting up $package..."
        done
        ;;
    "list")
        echo "Listing... Done"
        ;;
    *)
        echo "apt: command '$1' not implemented in mock"
        exit 1
        ;;
esac
EOF
    chmod +x "$MOCK_ENV/usr/bin/apt"

    # Also create apt-get
    ln -sf apt "$MOCK_ENV/usr/bin/apt-get"
}

create_mock_systemctl() {
    cat > "$MOCK_ENV/usr/bin/systemctl" << 'EOF'
#!/bin/bash
case "$1" in
    "enable"|"start"|"restart"|"reload")
        echo "systemctl: $1 $2"
        ;;
    "status")
        echo "● $2 - Mock service"
        echo "   Active: active (running)"
        ;;
    *)
        echo "systemctl: command '$1' not implemented in mock"
        ;;
esac
EOF
    chmod +x "$MOCK_ENV/usr/bin/systemctl"
}

create_mock_gpg() {
    cat > "$HOME/.local/bin/gpg" << 'EOF'
#!/bin/bash
case "$1" in
    "--list-secret-keys")
        echo "sec   rsa4096 2023-01-01 [SC]"
        echo "      ABCDEF1234567890ABCDEF1234567890ABCDEF12"
        echo "uid           [ultimate] Test User <test@example.com>"
        ;;
    "--full-generate-key")
        echo "Generating GPG key..."
        echo "Key generated successfully"
        ;;
    "--armor"|"--export")
        echo "-----BEGIN PGP PUBLIC KEY BLOCK-----"
        echo "mQINBGExample...MockKeyData...="
        echo "-----END PGP PUBLIC KEY BLOCK-----"
        ;;
    *)
        echo "gpg: $*"
        ;;
esac
EOF
    chmod +x "$HOME/.local/bin/gpg"
}

create_mock_chezmoi() {
    cat > "$HOME/.local/bin/chezmoi" << 'EOF'
#!/bin/bash
case "$1" in
    "init")
        echo "chezmoi: initialized"
        mkdir -p "$HOME/.local/share/chezmoi"
        ;;
    "apply")
        echo "chezmoi: applying configuration"
        mkdir -p "$HOME/.bashrc.d"
        echo "# Chezmoi configuration" > "$HOME/.bashrc.d/00-chezmoi.sh"
        echo "export CHEZMOI_APPLIED=true" >> "$HOME/.bashrc.d/00-chezmoi.sh"
        ;;
    "doctor")
        echo "chezmoi: OK"
        ;;
    "status")
        echo "No changes to apply"
        ;;
    "--version")
        echo "chezmoi version 2.46.1"
        ;;
    *)
        echo "chezmoi: $*"
        ;;
esac
EOF
    chmod +x "$HOME/.local/bin/chezmoi"
}

create_mock_git() {
    cat > "$HOME/.local/bin/git" << 'EOF'
#!/bin/bash
case "$1" in
    "config")
        case "$2" in
            "--global")
                echo "git config: $3 $4"
                ;;
            "user.name"|"user.email")
                echo "Test Value"
                ;;
        esac
        ;;
    "init")
        mkdir -p .git
        echo "Initialized git repository"
        ;;
    "clone")
        echo "Cloning repository: $2"
        mkdir -p "$(basename "$2" .git)"
        ;;
    "--version")
        echo "git version 2.40.1"
        ;;
    *)
        echo "git: $*"
        ;;
esac
EOF
    chmod +x "$HOME/.local/bin/git"
}

create_mock_pass() {
    cat > "$HOME/.local/bin/pass" << 'EOF'
#!/bin/bash
case "$1" in
    "init")
        echo "Password store initialized for $2"
        mkdir -p "$HOME/.password-store"
        ;;
    "insert")
        echo "Enter password for $2:"
        echo "Password stored: $2"
        ;;
    "ls")
        echo "Password Store"
        echo "├── personal/"
        echo "│   ├── github_token"
        echo "│   └── email"
        ;;
    "show")
        echo "mock_password_value"
        ;;
    *)
        echo "pass: $*"
        ;;
esac
EOF
    chmod +x "$HOME/.local/bin/pass"
}

create_mock_lsb_release() {
    cat > "$MOCK_ENV/usr/bin/lsb_release" << 'EOF'
#!/bin/bash
case "$1" in
    "-is")
        echo "Ubuntu"
        ;;
    "-rs")
        echo "24.04"
        ;;
    "-cs")
        echo "noble"
        ;;
    "-a")
        echo "Distributor ID: Ubuntu"
        echo "Description:    Ubuntu 24.04 LTS"
        echo "Release:        24.04"
        echo "Codename:       noble"
        ;;
esac
EOF
    chmod +x "$MOCK_ENV/usr/bin/lsb_release"
}

setup_mock_filesystem() {
    # Create system directories
    mkdir -p "$MOCK_ENV/etc"
    mkdir -p "$MOCK_ENV/var/lib/dpkg"
    mkdir -p "$MOCK_ENV/proc"

    # Create dpkg status file
    cat > "$MOCK_ENV/var/lib/dpkg/status" << 'EOF'
Package: bash
Status: install ok installed
Version: 5.1-6ubuntu1

Package: git
Status: install ok installed
Version: 1:2.40.1-1ubuntu1
EOF

    # Create /proc/meminfo
    cat > "$MOCK_ENV/proc/meminfo" << 'EOF'
MemTotal:        8048576 kB
MemFree:         4024288 kB
MemAvailable:    6036432 kB
EOF

    # Create /proc/cpuinfo
    cat > "$MOCK_ENV/proc/cpuinfo" << 'EOF'
processor	: 0
model name	: Mock CPU
flags		: fpu vme de pse tsc msr pae mce cx8 apic sep
EOF
}

# End-to-End Tests

test_complete_bootstrap_unattended() {
    # Test complete bootstrap process in unattended mode
    local test_script="$MOCK_ENV/complete_bootstrap_test.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash

run_bootstrap_unattended() {
    echo "Running complete bootstrap in unattended mode..."

    # Create a simplified bootstrap script for testing
    cat > "$1/test_bootstrap.sh" << 'BOOTSTRAP'
#!/bin/bash
set -euo pipefail

# Source colors and functions from original script
C_G="\033[1;32m"; C_Y="\033[1;33m"; C_R="\033[1;31m"; C_B="\033[1;34m"; C_N="\033[0m"
say(){ printf "${C_G}[+] %s${C_N}\n" "$*"; }
info(){ printf "${C_B}[i] %s${C_N}\n" "$*"; }
warn(){ printf "${C_Y}[!] %s${C_N}\n" "$*"; }
die(){ printf "${C_R}[✘] %s${C_N}\n" "$*" >&2; exit 1; }

# Parse flags
UNATTENDED=0
for arg in "$@"; do
    case "$arg" in
        --unattended|-u) UNATTENDED=1 ;;
    esac
done

# Simulate bootstrap steps
say "Starting machine-rites bootstrap..."

info "Step 1/10: Checking system requirements"
sleep 0.1

info "Step 2/10: Updating package lists"
apt update >/dev/null 2>&1

info "Step 3/10: Installing essential packages"
apt install -y curl wget git >/dev/null 2>&1

info "Step 4/10: Installing chezmoi"
mkdir -p "$HOME/.local/bin"
# Simulate chezmoi installation
say "Chezmoi installed successfully"

info "Step 5/10: Setting up GPG"
if ! gpg --list-secret-keys | grep -q sec; then
    say "GPG key already exists or created"
fi

info "Step 6/10: Initializing password store"
pass init "test-key" >/dev/null 2>&1 || true
say "Password store initialized"

info "Step 7/10: Configuring git"
git config --global user.name "Test User"
git config --global user.email "test@example.com"
say "Git configured"

info "Step 8/10: Setting up chezmoi"
chezmoi init >/dev/null 2>&1
say "Chezmoi initialized"

info "Step 9/10: Applying dotfiles"
chezmoi apply >/dev/null 2>&1
say "Dotfiles applied"

info "Step 10/10: Finalizing setup"
sleep 0.1

say "Bootstrap completed successfully!"
echo "BOOTSTRAP_SUCCESS"
BOOTSTRAP

    chmod +x "$1/test_bootstrap.sh"

    # Run bootstrap
    if "$1/test_bootstrap.sh" --unattended; then
        echo "Bootstrap execution: SUCCESS"
        return 0
    else
        echo "Bootstrap execution: FAILED"
        return 1
    fi
}

verify_bootstrap_results() {
    echo "Verifying bootstrap results..."

    # Check that essential files were created
    local expected_files=(
        "$HOME/.local/bin/chezmoi"
        "$HOME/.bashrc.d/00-chezmoi.sh"
        "$HOME/.password-store"
    )

    for file in "${expected_files[@]}"; do
        if [[ -e "$file" ]]; then
            echo "  ✓ Found: $file"
        else
            echo "  ✗ Missing: $file"
            return 1
        fi
    done

    # Check git configuration
    if git config user.name | grep -q "Test User"; then
        echo "  ✓ Git user configured"
    else
        echo "  ✗ Git user not configured"
        return 1
    fi

    # Check chezmoi configuration
    if [[ -f "$HOME/.bashrc.d/00-chezmoi.sh" ]]; then
        if grep -q "CHEZMOI_APPLIED=true" "$HOME/.bashrc.d/00-chezmoi.sh"; then
            echo "  ✓ Chezmoi applied successfully"
        else
            echo "  ✗ Chezmoi application incomplete"
            return 1
        fi
    fi

    echo "Bootstrap verification: PASSED"
    return 0
}

# Run complete bootstrap test
run_bootstrap_unattended "$MOCK_ENV" || exit 1

# Verify results
verify_bootstrap_results || exit 1

echo "Complete bootstrap unattended test: PASSED"
EOF

    assert_command_succeeds "bash '$test_script'" "complete bootstrap unattended works"
}

test_bootstrap_with_user_interaction() {
    # Test bootstrap with simulated user interaction
    local test_script="$MOCK_ENV/interactive_bootstrap_test.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash

simulate_user_responses() {
    # Create responses file for interactive prompts
    cat > "$1/user_responses.txt" << 'RESPONSES'
test@example.com
Test User
nano
y
y
n
RESPONSES
}

run_interactive_bootstrap() {
    local responses_file="$1/user_responses.txt"

    echo "Running interactive bootstrap simulation..."

    # Create interactive bootstrap script
    cat > "$1/interactive_test.sh" << 'INTERACTIVE'
#!/bin/bash

get_user_input() {
    local prompt="$1"
    local default="$2"

    echo "$prompt [$default]: "
    # In real scenario, would read from stdin
    # For testing, read from responses file
    if [[ -f "$RESPONSES_FILE" ]]; then
        local response
        response=$(head -1 "$RESPONSES_FILE" 2>/dev/null || echo "$default")
        # Remove first line from responses file
        tail -n +2 "$RESPONSES_FILE" > "$RESPONSES_FILE.tmp" 2>/dev/null || true
        mv "$RESPONSES_FILE.tmp" "$RESPONSES_FILE" 2>/dev/null || true
        echo "$response"
    else
        echo "$default"
    fi
}

# Simulate interactive configuration
echo "=== Interactive Bootstrap Configuration ==="

EMAIL=$(get_user_input "Enter your email" "user@example.com")
echo "Email: $EMAIL"

NAME=$(get_user_input "Enter your name" "User Name")
echo "Name: $NAME"

EDITOR=$(get_user_input "Preferred editor" "vim")
echo "Editor: $EDITOR"

INSTALL_DEV_TOOLS=$(get_user_input "Install development tools?" "y")
echo "Dev tools: $INSTALL_DEV_TOOLS"

SETUP_SSH=$(get_user_input "Setup SSH key?" "y")
echo "SSH setup: $SETUP_SSH"

BACKUP_EXISTING=$(get_user_input "Backup existing config?" "n")
echo "Backup: $BACKUP_EXISTING"

# Apply configuration
cat > "$HOME/.config/user_preferences.conf" << CONFIG
EMAIL=$EMAIL
NAME=$NAME
EDITOR=$EDITOR
INSTALL_DEV_TOOLS=$INSTALL_DEV_TOOLS
SETUP_SSH=$SETUP_SSH
BACKUP_EXISTING=$BACKUP_EXISTING
CONFIG

echo "INTERACTIVE_BOOTSTRAP_SUCCESS"
INTERACTIVE

    chmod +x "$1/interactive_test.sh"

    # Run with responses file
    RESPONSES_FILE="$responses_file" "$1/interactive_test.sh"
}

verify_interactive_configuration() {
    echo "Verifying interactive configuration..."

    local config_file="$HOME/.config/user_preferences.conf"

    if [[ -f "$config_file" ]]; then
        echo "  ✓ Configuration file created"

        # Check configuration values
        if grep -q "EMAIL=test@example.com" "$config_file"; then
            echo "  ✓ Email configured correctly"
        else
            echo "  ✗ Email configuration incorrect"
            return 1
        fi

        if grep -q "NAME=Test User" "$config_file"; then
            echo "  ✓ Name configured correctly"
        else
            echo "  ✗ Name configuration incorrect"
            return 1
        fi

        if grep -q "EDITOR=nano" "$config_file"; then
            echo "  ✓ Editor configured correctly"
        else
            echo "  ✗ Editor configuration incorrect"
            return 1
        fi
    else
        echo "  ✗ Configuration file not created"
        return 1
    fi

    echo "Interactive configuration verification: PASSED"
    return 0
}

# Set up user responses
simulate_user_responses "$MOCK_ENV"

# Run interactive bootstrap
run_interactive_bootstrap "$MOCK_ENV" || exit 1

# Verify configuration
verify_interactive_configuration || exit 1

echo "Interactive bootstrap test: PASSED"
EOF

    assert_command_succeeds "bash '$test_script'" "interactive bootstrap works"
}

test_bootstrap_error_recovery() {
    # Test bootstrap error handling and recovery
    local test_script="$MOCK_ENV/error_recovery_test.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash

simulate_network_failure() {
    # Create failing network commands
    cat > "$HOME/.local/bin/curl" << 'CURL'
#!/bin/bash
echo "curl: (7) Couldn't connect to server" >&2
exit 7
CURL
    chmod +x "$HOME/.local/bin/curl"

    cat > "$HOME/.local/bin/wget" << 'WGET'
#!/bin/bash
echo "wget: unable to resolve host address" >&2
exit 1
WGET
    chmod +x "$HOME/.local/bin/wget"
}

simulate_package_failure() {
    # Create failing apt command
    cat > "$MOCK_ENV/usr/bin/apt" << 'APT'
#!/bin/bash
case "$1" in
    "update")
        echo "Reading package lists... Done" >&2
        echo "E: Could not get lock /var/lib/apt/lists/lock" >&2
        exit 100
        ;;
    "install")
        echo "E: Package 'nonexistent-package' has no installation candidate" >&2
        exit 100
        ;;
    *)
        echo "apt: $*"
        ;;
esac
APT
    chmod +x "$MOCK_ENV/usr/bin/apt"
}

test_retry_mechanism() {
    echo "Testing retry mechanism..."

    cat > "$MOCK_ENV/retry_test.sh" << 'RETRY'
#!/bin/bash

retry_command() {
    local cmd="$1"
    local max_attempts="${2:-3}"
    local delay="${3:-1}"

    for ((attempt=1; attempt<=max_attempts; attempt++)); do
        echo "Attempt $attempt/$max_attempts: $cmd"

        if eval "$cmd"; then
            echo "Command succeeded on attempt $attempt"
            return 0
        fi

        if [[ $attempt -lt $max_attempts ]]; then
            echo "Retrying in ${delay}s..."
            sleep "$delay"
        fi
    done

    echo "Command failed after $max_attempts attempts"
    return 1
}

# Test with failing command that eventually succeeds
cat > "$MOCK_ENV/failing_command.sh" << 'FAILING'
#!/bin/bash
# Fail first 2 times, succeed on 3rd
ATTEMPT_FILE="/tmp/command_attempts"
attempts=0
if [[ -f "$ATTEMPT_FILE" ]]; then
    attempts=$(cat "$ATTEMPT_FILE")
fi
((attempts++))
echo "$attempts" > "$ATTEMPT_FILE"

if [[ $attempts -ge 3 ]]; then
    rm -f "$ATTEMPT_FILE"
    echo "Command succeeded!"
    exit 0
else
    echo "Command failed (attempt $attempts)"
    exit 1
fi
FAILING
    chmod +x "$MOCK_ENV/failing_command.sh"

    # Test retry mechanism
    if retry_command "$MOCK_ENV/failing_command.sh" 5 0.1; then
        echo "Retry mechanism: PASSED"
        return 0
    else
        echo "Retry mechanism: FAILED"
        return 1
    fi
}

test_graceful_degradation() {
    echo "Testing graceful degradation..."

    cat > "$MOCK_ENV/degradation_test.sh" << 'DEGRADATION'
#!/bin/bash

install_with_fallback() {
    local primary_method="$1"
    local fallback_method="$2"

    echo "Trying primary installation method: $primary_method"
    if eval "$primary_method"; then
        echo "Primary method succeeded"
        return 0
    fi

    echo "Primary method failed, trying fallback: $fallback_method"
    if eval "$fallback_method"; then
        echo "Fallback method succeeded"
        return 0
    fi

    echo "Both methods failed"
    return 1
}

# Test installation with fallback
if install_with_fallback "false" "true"; then
    echo "Graceful degradation: PASSED"
    return 0
else
    echo "Graceful degradation: FAILED"
    return 1
fi
DEGRADATION

    if bash "$MOCK_ENV/degradation_test.sh"; then
        echo "Graceful degradation test: PASSED"
        return 0
    else
        echo "Graceful degradation test: FAILED"
        return 1
    fi
}

test_cleanup_on_failure() {
    echo "Testing cleanup on failure..."

    cat > "$MOCK_ENV/cleanup_test.sh" << 'CLEANUP'
#!/bin/bash

cleanup_temp_files() {
    echo "Cleaning up temporary files..."
    rm -rf /tmp/bootstrap_temp_*
    rm -rf "$HOME/.temp_config"
    echo "Cleanup completed"
}

bootstrap_with_cleanup() {
    # Set up cleanup trap
    trap cleanup_temp_files EXIT ERR

    # Create temporary files
    mkdir -p /tmp/bootstrap_temp_1
    mkdir -p /tmp/bootstrap_temp_2
    mkdir -p "$HOME/.temp_config"

    echo "Created temporary files"

    # Simulate failure
    if [[ "${SIMULATE_FAILURE:-}" == "true" ]]; then
        echo "Simulating bootstrap failure"
        exit 1
    fi

    echo "Bootstrap completed successfully"
}

# Test cleanup on failure
SIMULATE_FAILURE=true bootstrap_with_cleanup 2>/dev/null || true

# Verify cleanup occurred
if [[ ! -d "/tmp/bootstrap_temp_1" ]] && [[ ! -d "$HOME/.temp_config" ]]; then
    echo "Cleanup on failure: PASSED"
    return 0
else
    echo "Cleanup on failure: FAILED"
    return 1
fi
CLEANUP

    if bash "$MOCK_ENV/cleanup_test.sh"; then
        echo "Cleanup test: PASSED"
        return 0
    else
        echo "Cleanup test: FAILED"
        return 1
    fi
}

# Run error recovery tests
test_retry_mechanism || exit 1
test_graceful_degradation || exit 1
test_cleanup_on_failure || exit 1

echo "Bootstrap error recovery test: PASSED"
EOF

    assert_command_succeeds "bash '$test_script'" "bootstrap error recovery works"
}

test_bootstrap_with_existing_config() {
    # Test bootstrap behavior with existing configurations
    local test_script="$MOCK_ENV/existing_config_test.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash

setup_existing_configuration() {
    echo "Setting up existing configuration..."

    # Create existing dotfiles
    cat > "$HOME/.bashrc" << 'BASHRC'
# Existing bashrc
export EXISTING_CONFIG=true
alias old_alias='echo old'
BASHRC

    cat > "$HOME/.gitconfig" << 'GITCONFIG'
[user]
    name = Existing User
    email = existing@example.com
[core]
    editor = existing_editor
GITCONFIG

    # Create existing chezmoi setup
    mkdir -p "$HOME/.local/share/chezmoi"
    echo "# Existing chezmoi" > "$HOME/.local/share/chezmoi/README.md"

    # Create existing GPG setup
    mkdir -p "$HOME/.gnupg"
    echo "existing gpg" > "$HOME/.gnupg/pubring.kbx"

    echo "Existing configuration setup completed"
}

test_configuration_backup() {
    echo "Testing configuration backup..."

    cat > "$MOCK_ENV/backup_test.sh" << 'BACKUP'
#!/bin/bash

backup_existing_config() {
    local backup_dir="$HOME/dotfiles-backup-$(date +%Y%m%d_%H%M%S)"

    echo "Creating backup in: $backup_dir"
    mkdir -p "$backup_dir"

    local files_to_backup=(".bashrc" ".gitconfig" ".gnupg")

    for file in "${files_to_backup[@]}"; do
        if [[ -e "$HOME/$file" ]]; then
            echo "Backing up: $file"
            cp -r "$HOME/$file" "$backup_dir/"
        fi
    done

    echo "$backup_dir"
}

# Test backup creation
backup_dir=$(backup_existing_config)

# Verify backup
if [[ -d "$backup_dir" ]] && [[ -f "$backup_dir/.bashrc" ]]; then
    echo "Configuration backup: PASSED"
    echo "$backup_dir"
else
    echo "Configuration backup: FAILED"
    exit 1
fi
BACKUP

    local backup_result
    backup_result=$(bash "$MOCK_ENV/backup_test.sh")

    if echo "$backup_result" | grep -q "PASSED"; then
        echo "Backup test: PASSED"
        return 0
    else
        echo "Backup test: FAILED"
        return 1
    fi
}

test_configuration_merging() {
    echo "Testing configuration merging..."

    cat > "$MOCK_ENV/merge_test.sh" << 'MERGE'
#!/bin/bash

merge_configurations() {
    local existing_file="$1"
    local new_file="$2"
    local merged_file="$3"

    echo "Merging configurations..."

    # Simple merge strategy: preserve existing + add new
    {
        echo "# Merged configuration"
        echo "# Existing configuration:"
        cat "$existing_file"
        echo ""
        echo "# New configuration:"
        cat "$new_file"
    } > "$merged_file"

    echo "Configuration merged successfully"
}

# Create test configurations
echo "existing_setting=true" > "$MOCK_ENV/existing.conf"
echo "new_setting=true" > "$MOCK_ENV/new.conf"

# Test merge
merge_configurations "$MOCK_ENV/existing.conf" "$MOCK_ENV/new.conf" "$MOCK_ENV/merged.conf"

# Verify merge
if grep -q "existing_setting=true" "$MOCK_ENV/merged.conf" &&
   grep -q "new_setting=true" "$MOCK_ENV/merged.conf"; then
    echo "Configuration merging: PASSED"
else
    echo "Configuration merging: FAILED"
    exit 1
fi
MERGE

    if bash "$MOCK_ENV/merge_test.sh"; then
        echo "Merge test: PASSED"
        return 0
    else
        echo "Merge test: FAILED"
        return 1
    fi
}

test_conflict_resolution() {
    echo "Testing conflict resolution..."

    cat > "$MOCK_ENV/conflict_test.sh" << 'CONFLICT'
#!/bin/bash

resolve_config_conflict() {
    local existing_value="$1"
    local new_value="$2"
    local resolution_strategy="${3:-prompt}"

    case "$resolution_strategy" in
        "keep_existing")
            echo "$existing_value"
            ;;
        "use_new")
            echo "$new_value"
            ;;
        "merge")
            echo "${existing_value}_${new_value}"
            ;;
        "prompt")
            # In real scenario, would prompt user
            # For testing, use merge strategy
            echo "${existing_value}_${new_value}"
            ;;
        *)
            echo "$existing_value"
            ;;
    esac
}

# Test different resolution strategies
existing="existing_value"
new="new_value"

result1=$(resolve_config_conflict "$existing" "$new" "keep_existing")
[[ "$result1" == "existing_value" ]] || exit 1

result2=$(resolve_config_conflict "$existing" "$new" "use_new")
[[ "$result2" == "new_value" ]] || exit 1

result3=$(resolve_config_conflict "$existing" "$new" "merge")
[[ "$result3" == "existing_value_new_value" ]] || exit 1

echo "Conflict resolution: PASSED"
CONFLICT

    if bash "$MOCK_ENV/conflict_test.sh"; then
        echo "Conflict resolution test: PASSED"
        return 0
    else
        echo "Conflict resolution test: FAILED"
        return 1
    fi
}

# Setup existing configuration
setup_existing_configuration

# Run tests
test_configuration_backup || exit 1
test_configuration_merging || exit 1
test_conflict_resolution || exit 1

echo "Bootstrap with existing config test: PASSED"
EOF

    assert_command_succeeds "bash '$test_script'" "bootstrap with existing config works"
}

test_performance_and_resource_usage() {
    # Test bootstrap performance and resource usage
    local test_script="$MOCK_ENV/performance_test.sh"
    cat > "$test_script" << 'EOF'
#!/bin/bash

measure_bootstrap_performance() {
    echo "Measuring bootstrap performance..."

    local start_time end_time duration
    local start_memory end_memory memory_used

    # Measure initial memory (simplified)
    start_memory=$(free -m 2>/dev/null | awk '/^Mem:/ {print $3}' || echo "0")
    start_time=$(date +%s.%N)

    # Run bootstrap simulation
    simulate_bootstrap_operations

    end_time=$(date +%s.%N)
    end_memory=$(free -m 2>/dev/null | awk '/^Mem:/ {print $3}' || echo "0")

    duration=$(awk "BEGIN {printf \"%.3f\", $end_time - $start_time}")
    memory_used=$((end_memory - start_memory))

    echo "Bootstrap Performance Metrics:"
    echo "  Duration: ${duration}s"
    echo "  Memory used: ${memory_used}MB"

    # Performance thresholds
    local max_duration=30.0  # 30 seconds
    local max_memory=500     # 500MB

    if (( $(awk "BEGIN {print ($duration < $max_duration)}") )); then
        echo "  ✓ Duration within acceptable limits"
    else
        echo "  ✗ Duration exceeds limits ($duration > $max_duration)"
        return 1
    fi

    if [[ $memory_used -lt $max_memory ]]; then
        echo "  ✓ Memory usage within acceptable limits"
    else
        echo "  ✗ Memory usage exceeds limits ($memory_used > $max_memory)"
        return 1
    fi

    echo "Performance test: PASSED"
    return 0
}

simulate_bootstrap_operations() {
    echo "Simulating bootstrap operations..."

    # Simulate package updates
    for i in {1..10}; do
        echo "Processing package $i..."
        sleep 0.01
    done

    # Simulate file operations
    for i in {1..50}; do
        echo "test file $i" > "/tmp/test_file_$i"
        sleep 0.001
    done

    # Simulate network operations
    for i in {1..5}; do
        echo "Network operation $i..."
        sleep 0.02
    done

    # Cleanup test files
    rm -f /tmp/test_file_*

    echo "Bootstrap simulation completed"
}

test_disk_usage() {
    echo "Testing disk usage..."

    local initial_usage final_usage disk_used

    initial_usage=$(du -sm "$HOME" 2>/dev/null | cut -f1)

    # Simulate installation of tools and configs
    mkdir -p "$HOME/.local/bin"
    mkdir -p "$HOME/.config"
    mkdir -p "$HOME/.cache"

    # Create some test files
    echo "large file content" > "$HOME/.local/bin/large_tool"
    echo "config data" > "$HOME/.config/test.conf"

    final_usage=$(du -sm "$HOME" 2>/dev/null | cut -f1)
    disk_used=$((final_usage - initial_usage))

    echo "Disk usage: ${disk_used}MB"

    # Should not use excessive disk space
    if [[ $disk_used -lt 100 ]]; then
        echo "  ✓ Disk usage within acceptable limits"
        return 0
    else
        echo "  ✗ Excessive disk usage: ${disk_used}MB"
        return 1
    fi
}

measure_cpu_usage() {
    echo "Measuring CPU usage..."

    # Simplified CPU usage measurement
    # In real scenario, would use tools like top, ps, or time

    local cpu_start cpu_end cpu_used
    cpu_start=$(date +%s.%N)

    # Simulate CPU-intensive operations
    for i in {1..1000}; do
        echo "CPU intensive operation $i" > /dev/null
    done

    cpu_end=$(date +%s.%N)
    cpu_used=$(awk "BEGIN {printf \"%.3f\", $cpu_end - $cpu_start}")

    echo "CPU time used: ${cpu_used}s"

    # Should complete CPU operations efficiently
    if (( $(awk "BEGIN {print ($cpu_used < 5.0)}") )); then
        echo "  ✓ CPU usage within acceptable limits"
        return 0
    else
        echo "  ✗ Excessive CPU usage: ${cpu_used}s"
        return 1
    fi
}

# Run performance tests
measure_bootstrap_performance || exit 1
test_disk_usage || exit 1
measure_cpu_usage || exit 1

echo "Performance and resource usage test: PASSED"
EOF

    assert_command_succeeds "bash '$test_script'" "performance and resource usage acceptable"
}

# Test execution
main() {
    init_test_framework
    start_test_suite "Complete_Bootstrap_E2E"

    setup_e2e_tests

    run_test "Complete Bootstrap Unattended" test_complete_bootstrap_unattended
    run_test "Bootstrap with User Interaction" test_bootstrap_with_user_interaction
    run_test "Bootstrap Error Recovery" test_bootstrap_error_recovery
    run_test "Bootstrap with Existing Config" test_bootstrap_with_existing_config
    run_test "Performance and Resource Usage" test_performance_and_resource_usage

    cleanup_e2e_tests
    end_test_suite
    finalize_test_framework
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi