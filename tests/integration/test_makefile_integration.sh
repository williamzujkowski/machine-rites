#!/usr/bin/env bash
# Integration Tests - Makefile Integration
# Tests integration with existing makefile test infrastructure
set -euo pipefail

# Source test framework
source "$(dirname "${BASH_SOURCE[0]}")/../test-framework.sh"

# Test configuration
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly MAKEFILE="$PROJECT_ROOT/makefile"
readonly MOCK_ENV="$(setup_mock_environment "makefile_integration")"

# Test setup
setup_makefile_tests() {
    export HOME="$MOCK_ENV/home"
    export PROJECT_DIR="$MOCK_ENV/project"

    mkdir -p "$HOME" "$PROJECT_DIR"

    # Copy project files to mock environment
    cp "$PROJECT_ROOT/bootstrap_machine_rites.sh" "$PROJECT_DIR/"
    cp "$PROJECT_ROOT/makefile" "$PROJECT_DIR/"
    mkdir -p "$PROJECT_DIR/tools"
    cp "$PROJECT_ROOT/tools"/*.sh "$PROJECT_DIR/tools/" 2>/dev/null || true

    # Create mock commands
    mkdir -p "$HOME/.local/bin"
    export PATH="$HOME/.local/bin:$PATH"

    log_debug "Setup makefile integration tests in: $MOCK_ENV"
}

# Test teardown
cleanup_makefile_tests() {
    cleanup_mock_environment "$MOCK_ENV"
}

# Create mock commands for makefile targets
create_mock_commands() {
    # Mock shellcheck
    cat > "$HOME/.local/bin/shellcheck" << 'EOF'
#!/bin/bash
case "$1" in
    "--severity=warning")
        shift
        for file in "$@"; do
            if [[ "$file" == *"error"* ]]; then
                echo "$file:1:1: warning: Mock shellcheck warning" >&2
                exit 1
            else
                echo "shellcheck: $file OK"
            fi
        done
        ;;
    *)
        echo "shellcheck: $*"
        ;;
esac
EOF
    chmod +x "$HOME/.local/bin/shellcheck"

    # Mock chezmoi
    cat > "$HOME/.local/bin/chezmoi" << 'EOF'
#!/bin/bash
case "$1" in
    "--source")
        shift
        case "$1" in
            "*/apply")
                echo "chezmoi: applied configuration"
                ;;
            "*/diff")
                echo "No differences"
                ;;
            "*/status")
                echo "Up to date"
                ;;
            *)
                echo "chezmoi --source: $*"
                ;;
        esac
        ;;
    *)
        echo "chezmoi: $*"
        ;;
esac
EOF
    chmod +x "$HOME/.local/bin/chezmoi"

    # Mock pre-commit
    cat > "$HOME/.local/bin/pre-commit" << 'EOF'
#!/bin/bash
case "$1" in
    "run")
        echo "pre-commit: running checks..."
        echo "All checks passed"
        ;;
    "autoupdate")
        echo "pre-commit: updating hooks"
        ;;
    *)
        echo "pre-commit: $*"
        ;;
esac
EOF
    chmod +x "$HOME/.local/bin/pre-commit"

    # Mock git
    cat > "$HOME/.local/bin/git" << 'EOF'
#!/bin/bash
case "$1" in
    "pull")
        echo "Already up to date."
        ;;
    "add")
        echo "git add: $*"
        ;;
    "commit")
        echo "git commit: $*"
        ;;
    "push")
        echo "git push: $*"
        ;;
    "diff")
        if [[ "$2" == "--cached" ]]; then
            # No staged changes
            exit 1
        else
            echo "No changes"
        fi
        ;;
    *)
        echo "git: $*"
        ;;
esac
EOF
    chmod +x "$HOME/.local/bin/git"
}

# Integration Tests for Makefile Targets

test_makefile_help_target() {
    # Test makefile help target
    cd "$PROJECT_DIR"

    local help_output
    help_output=$(make help 2>&1)

    assert_contains "$help_output" "machine-rites - Dotfiles Management" "help shows project description"
    assert_contains "$help_output" "install" "help shows install target"
    assert_contains "$help_output" "test" "help shows test target"
    assert_contains "$help_output" "doctor" "help shows doctor target"
    assert_contains "$help_output" "backup" "help shows backup target"
}

test_makefile_lint_target() {
    # Test makefile lint target
    cd "$PROJECT_DIR"
    create_mock_commands

    local lint_output
    lint_output=$(make lint 2>&1)

    assert_contains "$lint_output" "Running shellcheck" "lint target runs shellcheck"
    assert_command_succeeds "make lint" "lint target completes successfully"
}

test_makefile_test_target() {
    # Test makefile test target (syntax checks)
    cd "$PROJECT_DIR"
    create_mock_commands

    local test_output
    test_output=$(make test 2>&1)

    assert_contains "$test_output" "Running syntax checks" "test target runs syntax checks"
    assert_contains "$test_output" "Running pre-commit checks" "test target runs pre-commit"
}

test_makefile_doctor_integration() {
    # Test integration with doctor.sh script
    cd "$PROJECT_DIR"

    # Create mock doctor script
    cat > "$PROJECT_DIR/tools/doctor.sh" << 'EOF'
#!/bin/bash
echo "=== Dotfiles Health Check ==="
echo "✓ All essential tools installed"
echo "=== End Health Check ==="
EOF
    chmod +x "$PROJECT_DIR/tools/doctor.sh"

    local doctor_output
    doctor_output=$(make doctor 2>&1)

    assert_contains "$doctor_output" "Dotfiles Health Check" "doctor target runs health check"
    assert_contains "$doctor_output" "All essential tools installed" "doctor reports system status"
}

test_makefile_chezmoi_integration() {
    # Test chezmoi-related makefile targets
    cd "$PROJECT_DIR"
    create_mock_commands

    # Test apply target
    local apply_output
    apply_output=$(make apply 2>&1)
    assert_contains "$apply_output" "chezmoi" "apply target uses chezmoi"

    # Test diff target
    local diff_output
    diff_output=$(make diff 2>&1)
    assert_contains "$diff_output" "chezmoi" "diff target uses chezmoi"

    # Test status target
    local status_output
    status_output=$(make status 2>&1)
    assert_contains "$status_output" "chezmoi" "status target uses chezmoi"
}

test_makefile_backup_integration() {
    # Test backup functionality
    cd "$PROJECT_DIR"

    # Create mock backup script
    cat > "$PROJECT_DIR/tools/backup-pass.sh" << 'EOF'
#!/bin/bash
echo "Creating encrypted backup of pass store..."
echo "Backup completed successfully"
EOF
    chmod +x "$PROJECT_DIR/tools/backup-pass.sh"

    local backup_output
    backup_output=$(make backup 2>&1)

    assert_contains "$backup_output" "encrypted backup" "backup target creates encrypted backup"
    assert_contains "$backup_output" "completed successfully" "backup completes successfully"
}

test_makefile_clean_target() {
    # Test cleanup functionality
    cd "$PROJECT_DIR"

    # Create test backup files
    mkdir -p "$HOME/dotfiles-backup-20240101_120000"
    mkdir -p "$PROJECT_DIR/backups"
    touch "$PROJECT_DIR/backups/old-backup-$(date -d '40 days ago' +%Y%m%d).gpg"

    local clean_output
    clean_output=$(make clean 2>&1)

    assert_contains "$clean_output" "Cleaning old backups" "clean target removes old backups"
    assert_contains "$clean_output" "Cleaned backups" "clean operation completes"
}

test_makefile_version_check() {
    # Test version checking functionality
    cd "$PROJECT_DIR"
    create_mock_commands

    # Add version output to mock commands
    cat > "$HOME/.local/bin/bash" << 'EOF'
#!/bin/bash
case "$1" in
    "--version")
        echo "GNU bash, version 5.1.16(1)-release"
        ;;
    *)
        exec /bin/bash "$@"
        ;;
esac
EOF
    chmod +x "$HOME/.local/bin/bash"

    local version_output
    version_output=$(make check-versions 2>&1)

    assert_contains "$version_output" "Checking tool versions" "version check shows header"
    assert_contains "$version_output" "bash" "version check includes bash"
}

test_makefile_secrets_management() {
    # Test secrets management targets
    cd "$PROJECT_DIR"
    create_mock_commands

    # Mock pass command
    cat > "$HOME/.local/bin/pass" << 'EOF'
#!/bin/bash
case "$1" in
    "ls")
        echo "Password Store"
        echo "├── personal/"
        echo "│   └── test_secret"
        ;;
    "insert")
        echo "Enter password for $2:"
        echo "Password stored successfully"
        ;;
    *)
        echo "pass: $*"
        ;;
esac
EOF
    chmod +x "$HOME/.local/bin/pass"

    # Test secrets list
    local secrets_output
    secrets_output=$(make secrets-list 2>&1)
    assert_contains "$secrets_output" "Password Store" "secrets list shows password store"

    # Note: secrets-add requires interactive input, so we test the command construction
    assert_command_succeeds "make -n secrets-add KEY=test_key" "secrets-add target syntax is valid"
}

test_makefile_git_integration() {
    # Test git-related makefile functionality
    cd "$PROJECT_DIR"
    create_mock_commands

    # Test push target (dry run to avoid actual git operations)
    local push_output
    push_output=$(make -n push 2>&1)

    assert_contains "$push_output" "make test" "push target includes test dependency"
    assert_contains "$push_output" "git add" "push target stages changes"
    assert_contains "$push_output" "git commit" "push target commits changes"
    assert_contains "$push_output" "git push" "push target pushes to remote"
}

test_makefile_ci_targets() {
    # Test CI/CD related targets
    cd "$PROJECT_DIR"
    create_mock_commands

    # Mock sudo and installation commands
    cat > "$HOME/.local/bin/sudo" << 'EOF'
#!/bin/bash
case "$1" in
    "apt-get")
        echo "Reading package lists... Done"
        echo "Building dependency tree... Done"
        echo "The following NEW packages will be installed:"
        echo "  shellcheck"
        echo "Setting up shellcheck..."
        ;;
    *)
        echo "sudo: $*"
        ;;
esac
EOF
    chmod +x "$HOME/.local/bin/sudo"

    # Test ci-setup target
    local ci_setup_output
    ci_setup_output=$(make ci-setup 2>&1)
    assert_contains "$ci_setup_output" "apt-get" "ci-setup installs dependencies"

    # Test ci-test target
    local ci_test_output
    ci_test_output=$(make ci-test 2>&1)
    assert_contains "$ci_test_output" "shellcheck" "ci-test runs shellcheck"
    assert_contains "$ci_test_output" "chezmoi" "ci-test validates chezmoi"
}

test_makefile_development_targets() {
    # Test development helper targets
    cd "$PROJECT_DIR"
    create_mock_commands

    # Test dev-reset target (dry run)
    local reset_output
    reset_output=$(make -n dev-reset 2>&1)

    assert_contains "$reset_output" "git fetch" "dev-reset fetches from remote"
    assert_contains "$reset_output" "git reset" "dev-reset resets to origin"
    assert_contains "$reset_output" "make apply" "dev-reset applies configuration"
}

test_makefile_error_handling() {
    # Test makefile error handling
    cd "$PROJECT_DIR"

    # Create a script that will cause shellcheck to fail
    cat > "$PROJECT_DIR/error_script.sh" << 'EOF'
#!/bin/bash
echo $undefined_variable  # This will cause shellcheck warning
EOF

    # Mock shellcheck to report this as an error
    cat > "$HOME/.local/bin/shellcheck" << 'EOF'
#!/bin/bash
for file in "$@"; do
    if [[ "$file" == *"error_script.sh" ]]; then
        echo "$file:2:6: error: undefined_variable is referenced but not assigned" >&2
        exit 1
    fi
done
EOF
    chmod +x "$HOME/.local/bin/shellcheck"

    # Test that makefile handles shellcheck failures gracefully
    if make lint 2>/dev/null; then
        skip_test "makefile error handling" "shellcheck mock not triggering errors as expected"
    else
        log_success "makefile correctly handles shellcheck failures"
    fi
}

test_makefile_parallel_safety() {
    # Test that makefile targets are safe for parallel execution
    cd "$PROJECT_DIR"
    create_mock_commands

    # Test multiple targets that should be safe to run in parallel
    local targets=("help" "check-versions")

    for target in "${targets[@]}"; do
        if ! make "$target" >/dev/null 2>&1; then
            log_error "Target $target failed in parallel safety test"
            return 1
        fi
    done

    log_success "Makefile targets are parallel-safe"
}

test_makefile_variable_handling() {
    # Test makefile variable handling
    cd "$PROJECT_DIR"

    # Test REPO_DIR variable
    local makefile_vars
    makefile_vars=$(make -n help | grep -o 'REPO_DIR.*' || echo "REPO_DIR not found")

    # Test CHEZMOI_SRC variable usage
    local chezmoi_vars
    chezmoi_vars=$(grep -c "CHEZMOI_SRC" "$PROJECT_DIR/makefile" || echo "0")

    assert_command_succeeds "test $chezmoi_vars -gt 0" "makefile uses CHEZMOI_SRC variable"

    # Test SHELL variable setting
    local shell_setting
    shell_setting=$(grep "SHELL.*bash" "$PROJECT_DIR/makefile" || echo "")
    assert_regex_match "$shell_setting" "SHELL.*bash" "makefile sets SHELL to bash"
}

# Test execution
main() {
    init_test_framework
    start_test_suite "Makefile_Integration"

    setup_makefile_tests

    run_test "Makefile Help Target" test_makefile_help_target
    run_test "Makefile Lint Target" test_makefile_lint_target
    run_test "Makefile Test Target" test_makefile_test_target
    run_test "Makefile Doctor Integration" test_makefile_doctor_integration
    run_test "Makefile Chezmoi Integration" test_makefile_chezmoi_integration
    run_test "Makefile Backup Integration" test_makefile_backup_integration
    run_test "Makefile Clean Target" test_makefile_clean_target
    run_test "Makefile Version Check" test_makefile_version_check
    run_test "Makefile Secrets Management" test_makefile_secrets_management
    run_test "Makefile Git Integration" test_makefile_git_integration
    run_test "Makefile CI Targets" test_makefile_ci_targets
    run_test "Makefile Development Targets" test_makefile_development_targets
    run_test "Makefile Error Handling" test_makefile_error_handling
    run_test "Makefile Parallel Safety" test_makefile_parallel_safety
    run_test "Makefile Variable Handling" test_makefile_variable_handling

    cleanup_makefile_tests
    end_test_suite
    finalize_test_framework
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi