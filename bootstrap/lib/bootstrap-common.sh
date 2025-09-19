#!/usr/bin/env bash
# bootstrap/lib/bootstrap-common.sh - Bootstrap-specific common functions
#
# Provides module system functions and bootstrap-specific utilities
# Used across all bootstrap modules for consistent behavior
#
# Functions:
#   - module_validate()   : Validate module before execution
#   - module_execute()    : Execute module with error handling
#   - module_verify()     : Verify module execution success
#   - module_rollback()   : Rollback module changes
#   - load_module()       : Load and validate module
#   - run_module()        : Full module lifecycle execution
#
# Dependencies: lib/common.sh, lib/atomic.sh
# Idempotent: Yes
# Self-contained: No (requires lib dependencies)

set -euo pipefail

# Source required libraries
# shellcheck source=../../lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../lib/common.sh"
# shellcheck source=../../lib/atomic.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../lib/atomic.sh"

# Module system metadata
readonly BOOTSTRAP_LIB_VERSION="1.0.0"
readonly MODULE_INTERFACE_VERSION="1.0.0"

# Module state tracking
declare -A MODULE_STATE=()
declare -A MODULE_ROLLBACK_ACTIONS=()

# Function: module_validate
# Purpose: Validate module before execution
# Args: $1 - Module name
# Returns: 0 if valid, 1 if invalid
# Example: module_validate "00-prereqs"
module_validate() {
    local module_name="$1"
    local module_file="$BOOTSTRAP_DIR/modules/${module_name}.sh"

    [[ -f "$module_file" ]] || {
        warn "Module file not found: $module_file"
        return 1
    }

    [[ -x "$module_file" ]] || {
        warn "Module not executable: $module_file"
        return 1
    }

    # Check for required functions
    if ! grep -q "^validate()" "$module_file" 2>/dev/null; then
        warn "Module missing validate() function: $module_name"
        return 1
    fi

    if ! grep -q "^execute()" "$module_file" 2>/dev/null; then
        warn "Module missing execute() function: $module_name"
        return 1
    fi

    return 0
}

# Function: module_execute
# Purpose: Execute module with error handling and state tracking
# Args: $1 - Module name
# Returns: 0 if successful, 1 if failed
# Example: module_execute "00-prereqs"
module_execute() {
    local module_name="$1"
    local module_file="$BOOTSTRAP_DIR/modules/${module_name}.sh"

    info "Executing module: $module_name"
    MODULE_STATE["$module_name"]="executing"

    # Source the module
    # shellcheck disable=SC1090
    if ! source "$module_file"; then
        warn "Failed to source module: $module_name"
        MODULE_STATE["$module_name"]="failed"
        return 1
    fi

    # Run validate function
    if ! validate; then
        warn "Module validation failed: $module_name"
        MODULE_STATE["$module_name"]="validation_failed"
        return 1
    fi

    # Run execute function
    if ! execute; then
        warn "Module execution failed: $module_name"
        MODULE_STATE["$module_name"]="execution_failed"

        # Attempt rollback if function exists
        if declare -f rollback >/dev/null 2>&1; then
            warn "Attempting rollback for module: $module_name"
            rollback || warn "Rollback failed for module: $module_name"
        fi

        return 1
    fi

    # Run verify function if it exists
    if declare -f verify >/dev/null 2>&1; then
        if ! verify; then
            warn "Module verification failed: $module_name"
            MODULE_STATE["$module_name"]="verification_failed"
            return 1
        fi
    fi

    MODULE_STATE["$module_name"]="completed"
    say "Module completed successfully: $module_name"
    return 0
}

# Function: module_rollback
# Purpose: Rollback module changes
# Args: $1 - Module name
# Returns: 0 if successful, 1 if failed
# Example: module_rollback "00-prereqs"
module_rollback() {
    local module_name="$1"
    local module_file="$BOOTSTRAP_DIR/modules/${module_name}.sh"

    info "Rolling back module: $module_name"

    # Source the module
    # shellcheck disable=SC1090
    if ! source "$module_file"; then
        warn "Failed to source module for rollback: $module_name"
        return 1
    fi

    # Run rollback function if it exists
    if declare -f rollback >/dev/null 2>&1; then
        if rollback; then
            say "Module rollback successful: $module_name"
            MODULE_STATE["$module_name"]="rolled_back"
            return 0
        else
            warn "Module rollback failed: $module_name"
            MODULE_STATE["$module_name"]="rollback_failed"
            return 1
        fi
    else
        warn "No rollback function available for module: $module_name"
        return 1
    fi
}

# Function: load_module
# Purpose: Load and validate module without executing
# Args: $1 - Module name
# Returns: 0 if loaded successfully, 1 if failed
# Example: load_module "00-prereqs"
load_module() {
    local module_name="$1"

    module_validate "$module_name" || return 1

    info "Module loaded: $module_name"
    return 0
}

# Function: run_module
# Purpose: Full module lifecycle execution (validate, execute, verify)
# Args: $1 - Module name
# Returns: 0 if successful, 1 if failed
# Example: run_module "00-prereqs"
run_module() {
    local module_name="$1"

    load_module "$module_name" || return 1
    module_execute "$module_name" || return 1

    return 0
}

# Function: get_module_state
# Purpose: Get current state of a module
# Args: $1 - Module name
# Returns: 0 and prints state
# Example: state=$(get_module_state "00-prereqs")
get_module_state() {
    local module_name="$1"
    echo "${MODULE_STATE[$module_name]:-not_started}"
}

# Function: list_modules
# Purpose: List all available modules in dependency order
# Args: None
# Returns: 0 and prints module list
# Example: modules=$(list_modules)
list_modules() {
    local module_dir="$BOOTSTRAP_DIR/modules"

    if [[ ! -d "$module_dir" ]]; then
        warn "Module directory not found: $module_dir"
        return 1
    fi

    # List modules in numeric order (dependency order)
    find "$module_dir" -name "*.sh" -type f | \
        sort | \
        sed 's|.*/||; s|\.sh$||'
}

# Function: module_dependencies_met
# Purpose: Check if module dependencies are satisfied
# Args: $1 - Module name
# Returns: 0 if dependencies met, 1 if not
# Example: module_dependencies_met "30-chezmoi"
module_dependencies_met() {
    local module_name="$1"
    local module_number="${module_name%%-*}"

    # Simple dependency check: all lower-numbered modules must be completed
    local dep_modules
    dep_modules=$(list_modules | grep -E "^[0-$(($module_number - 1))]")

    local dep_module
    for dep_module in $dep_modules; do
        local state
        state=$(get_module_state "$dep_module")
        if [[ "$state" != "completed" ]]; then
            warn "Dependency not met: $dep_module (state: $state)"
            return 1
        fi
    done

    return 0
}

# Function: should_skip_module
# Purpose: Check if module should be skipped based on flags
# Args: $1 - Module name
# Returns: 0 if should skip, 1 if should run
# Example: should_skip_module "60-devtools"
should_skip_module() {
    local module_name="$1"
    local skip_var="SKIP_$(echo "$module_name" | tr '[:lower:]-' '[:upper:]_')"

    # Check environment variable
    if [[ "${!skip_var:-0}" == "1" ]]; then
        info "Skipping module due to $skip_var=1: $module_name"
        return 0
    fi

    # Check global skip patterns
    local pattern
    for pattern in ${SKIP_MODULES:-}; do
        if [[ "$module_name" == *"$pattern"* ]]; then
            info "Skipping module due to pattern match '$pattern': $module_name"
            return 0
        fi
    done

    return 1
}

# Function: get_module_metadata
# Purpose: Extract metadata from module file
# Args: $1 - Module name
# Returns: 0 and prints metadata
# Example: get_module_metadata "00-prereqs"
get_module_metadata() {
    local module_name="$1"
    local module_file="$BOOTSTRAP_DIR/modules/${module_name}.sh"

    if [[ ! -f "$module_file" ]]; then
        echo "name=$module_name"
        echo "status=missing"
        return 1
    fi

    # Extract metadata from comments
    local description
    description=$(grep -m1 "^# Description:" "$module_file" 2>/dev/null | cut -d: -f2- | xargs || echo "No description")

    local version
    version=$(grep -m1 "^# Version:" "$module_file" 2>/dev/null | cut -d: -f2- | xargs || echo "1.0.0")

    local dependencies
    dependencies=$(grep -m1 "^# Dependencies:" "$module_file" 2>/dev/null | cut -d: -f2- | xargs || echo "none")

    echo "name=$module_name"
    echo "description=$description"
    echo "version=$version"
    echo "dependencies=$dependencies"
    echo "status=${MODULE_STATE[$module_name]:-not_started}"
}

# Source guard
if [[ -n "${__BOOTSTRAP_COMMON_LOADED:-}" ]]; then
    return 0
fi

readonly __BOOTSTRAP_COMMON_LOADED=1

# Set default bootstrap directory if not set
export BOOTSTRAP_DIR="${BOOTSTRAP_DIR:-$(dirname "$(dirname "${BASH_SOURCE[0]}")")}"