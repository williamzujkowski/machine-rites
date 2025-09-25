#!/usr/bin/env bash
# lib/validation.sh - Input validation functions for machine-rites
#
# Provides robust input validation and sanitization functions
# Ensures data integrity and security across all machine-rites scripts
#
# Functions:
#   - validate_email()     : Email address validation
#   - validate_url()       : URL validation
#   - validate_path()      : File/directory path validation
#   - validate_hostname()  : Hostname validation
#   - validate_port()      : Port number validation
#   - validate_ip()        : IP address validation
#   - sanitize_filename()  : Safe filename sanitization
#   - is_safe_string()     : Check for safe shell string
#
# Dependencies: common.sh (optional)
# Idempotent: Yes
# Self-contained: Yes

set -euo pipefail

# Source guard to prevent multiple loading
if [[ -n "${__LIB_VALIDATION_LOADED:-}" ]]; then
    return 0
fi

# Load common functions if available
if [[ -f "${BASH_SOURCE[0]%/*}/common.sh" ]]; then
    # shellcheck source=./common.sh
    source "${BASH_SOURCE[0]%/*}/common.sh"
fi

# Function: validate_email
# Purpose: Validate email address format
# Args: $1 - Email address to validate
# Returns: 0 if valid, 1 if invalid
# Example: validate_email "user@example.com" && echo "Valid"
validate_email() {
    local email="$1"
    local regex='^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'

    [[ -n "$email" ]] || return 1
    [[ ${#email} -le 254 ]] || return 1  # RFC 5321 limit
    [[ $email =~ $regex ]]
}

# Function: validate_url
# Purpose: Validate URL format (http/https)
# Args: $1 - URL to validate
# Returns: 0 if valid, 1 if invalid
# Example: validate_url "https://example.com" && echo "Valid"
validate_url() {
    local url="$1"
    local regex='^https?://[a-zA-Z0-9.-]+([/:?#].*)?$'

    [[ -n "$url" ]] || return 1
    [[ ${#url} -le 2048 ]] || return 1  # Reasonable URL length limit
    [[ $url =~ $regex ]]
}

# Function: validate_path
# Purpose: Validate file/directory path (absolute or relative)
# Args: $1 - Path to validate, $2 - type (file|dir|any) [optional]
# Returns: 0 if valid, 1 if invalid
# Example: validate_path "/home/user" "dir" && echo "Valid directory path"
validate_path() {
    local path="$1"
    local type="${2:-any}"

    [[ -n "$path" ]] || return 1

    # Check for dangerous patterns
    [[ "$path" != *"/../"* ]] || return 1  # No parent directory traversal
    [[ "$path" != *"//"* ]] || return 1    # No double slashes
    [[ "$path" != *$'\n'* ]] || return 1   # No newlines
    [[ "$path" != *$'\r'* ]] || return 1   # No carriage returns

    # Check length (most filesystems limit paths to 4096 chars)
    [[ ${#path} -le 4096 ]] || return 1

    case "$type" in
        file)
            [[ -f "$path" ]] || return 1
            ;;
        dir)
            [[ -d "$path" ]] || return 1
            ;;
        any)
            [[ -e "$path" ]] || return 0  # Allow non-existent paths
            ;;
        *)
            [[ -n "${warn:-}" ]] && warn "validate_path: invalid type '$type'"
            return 1
            ;;
    esac

    return 0
}

# Function: validate_hostname
# Purpose: Validate hostname according to RFC standards
# Args: $1 - Hostname to validate
# Returns: 0 if valid, 1 if invalid
# Example: validate_hostname "example.com" && echo "Valid"
validate_hostname() {
    local hostname="$1"
    local label_regex='^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$'
    local fqdn_regex='^[a-zA-Z0-9]([a-zA-Z0-9.-]{0,253}[a-zA-Z0-9])?$'

    [[ -n "$hostname" ]] || return 1

    # Overall length check (RFC 1035)
    [[ ${#hostname} -le 253 ]] || return 1

    # FQDN format check
    [[ $hostname =~ $fqdn_regex ]] || return 1

    # Check each label (between dots)
    local IFS='.'
    local label
    for label in $hostname; do
        [[ ${#label} -le 63 ]] || return 1  # Label length limit
        [[ $label =~ $label_regex ]] || return 1
    done

    return 0
}

# Function: validate_port
# Purpose: Validate port number (1-65535)
# Args: $1 - Port number to validate
# Returns: 0 if valid, 1 if invalid
# Example: validate_port "8080" && echo "Valid"
validate_port() {
    local port="$1"

    [[ -n "$port" ]] || return 1
    [[ "$port" =~ ^[0-9]+$ ]] || return 1
    [[ "$port" -ge 1 && "$port" -le 65535 ]] || return 1

    return 0
}

# Function: validate_ip
# Purpose: Validate IPv4 address
# Args: $1 - IP address to validate
# Returns: 0 if valid, 1 if invalid
# Example: validate_ip "192.168.1.1" && echo "Valid"
validate_ip() {
    local ip="$1"
    local regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
    local octet

    [[ -n "$ip" ]] || return 1
    [[ $ip =~ $regex ]] || return 1

    # Check each octet is 0-255
    local IFS='.'
    for octet in $ip; do
        [[ "$octet" -ge 0 && "$octet" -le 255 ]] || return 1
        # No leading zeros (except for single 0)
        [[ "$octet" == "0" || "${octet:0:1}" != "0" ]] || return 1
    done

    return 0
}

# Function: sanitize_filename
# Purpose: Sanitize string for safe use as filename
# Args: $1 - String to sanitize, $2 - replacement char (optional, default: _)
# Returns: 0, prints sanitized filename
# Example: safe_name="$(sanitize_filename "My File!.txt")"
sanitize_filename() {
    local input="$1"
    local replacement="${2:-_}"
    local sanitized

    [[ -n "$input" ]] || return 1

    # Replace dangerous characters with replacement
    sanitized="$(echo "$input" | tr -d '\0' | tr '/' "$replacement")"
    sanitized="${sanitized//../$replacement}"  # No double dots
    sanitized="${sanitized//./$replacement}"   # No single dots at start

    # Remove control characters and other dangerous chars
    sanitized="$(echo "$sanitized" | tr -d '[:cntrl:]' | tr -d '<>:"|?*')"

    # Limit length to 255 characters (filesystem limit)
    if [[ ${#sanitized} -gt 255 ]]; then
        sanitized="${sanitized:0:252}..."
    fi

    # Ensure not empty after sanitization
    [[ -n "$sanitized" ]] || sanitized="file"

    echo "$sanitized"
}

# Function: is_safe_string
# Purpose: Check if string is safe for shell operations
# Args: $1 - String to check
# Returns: 0 if safe, 1 if potentially dangerous
# Example: is_safe_string "$user_input" || die "Unsafe input"
is_safe_string() {
    local string="$1"

    [[ -n "$string" ]] || return 1

    # Check for dangerous patterns
    [[ "$string" != *'$('* ]] || return 1      # No command substitution
    [[ "$string" != *'`'* ]] || return 1       # No backticks
    [[ "$string" != *';'* ]] || return 1       # No command separators
    [[ "$string" != *'|'* ]] || return 1       # No pipes
    [[ "$string" != *'&'* ]] || return 1       # No background
    [[ "$string" != *'>'* ]] || return 1       # No redirects
    [[ "$string" != *'<'* ]] || return 1       # No redirects
    [[ "$string" != *$'\n'* ]] || return 1     # No newlines
    [[ "$string" != *$'\r'* ]] || return 1     # No carriage returns
    [[ "$string" != *$'\t'* ]] || return 1     # No tabs

    # Check length (prevent buffer overflow attempts)
    [[ ${#string} -le 1024 ]] || return 1

    return 0
}

# Function: validate_version
# Purpose: Validate semantic version format (x.y.z)
# Args: $1 - Version string to validate
# Returns: 0 if valid, 1 if invalid
# Example: validate_version "1.2.3" && echo "Valid"
validate_version() {
    local version="$1"
    local regex='^([0-9]+)\.([0-9]+)\.([0-9]+)(-[a-zA-Z0-9.-]+)?(\+[a-zA-Z0-9.-]+)?$'

    [[ -n "$version" ]] || return 1
    [[ $version =~ $regex ]]
}

# Function: validate_git_repo
# Purpose: Validate git repository URL
# Args: $1 - Git repository URL
# Returns: 0 if valid, 1 if invalid
# Example: validate_git_repo "https://github.com/user/repo.git" && echo "Valid"
validate_git_repo() {
    local repo_url="$1"
    local https_regex='^https://[a-zA-Z0-9.-]+/[a-zA-Z0-9._/-]+\.git$'
    local ssh_regex='^git@[a-zA-Z0-9.-]+:[a-zA-Z0-9._/-]+\.git$'

    [[ -n "$repo_url" ]] || return 1
    [[ $repo_url =~ $https_regex || $repo_url =~ $ssh_regex ]]
}

# Function: validate_shell_identifier
# Purpose: Validate string as safe shell variable/function name
# Args: $1 - Identifier to validate
# Returns: 0 if valid, 1 if invalid
# Example: validate_shell_identifier "my_var" && echo "Safe"
validate_shell_identifier() {
    local identifier="$1"
    local regex='^[a-zA-Z_][a-zA-Z0-9_]*$'

    [[ -n "$identifier" ]] || return 1
    [[ ${#identifier} -le 64 ]] || return 1  # Reasonable length limit
    [[ $identifier =~ $regex ]]
}

# Function: validate_numeric
# Purpose: Validate numeric value within optional range
# Args: $1 - Value to validate, $2 - min (optional), $3 - max (optional)
# Returns: 0 if valid, 1 if invalid
# Example: validate_numeric "42" "1" "100" && echo "Valid"
validate_numeric() {
    local value="$1"
    local min="${2:-}"
    local max="${3:-}"

    [[ -n "$value" ]] || return 1
    [[ "$value" =~ ^-?[0-9]+(\.[0-9]+)?$ ]] || return 1

    if [[ -n "$min" ]]; then
        [[ $(echo "$value >= $min" | bc -l 2>/dev/null || echo 0) -eq 1 ]] || return 1
    fi

    if [[ -n "$max" ]]; then
        [[ $(echo "$value <= $max" | bc -l 2>/dev/null || echo 0) -eq 1 ]] || return 1
    fi

    return 0
}

# Library metadata
# shellcheck disable=SC2034  # Library version for compatibility checking
readonly LIB_VALIDATION_VERSION="1.0.0"
# shellcheck disable=SC2034  # Library guard to prevent multiple sourcing
readonly LIB_VALIDATION_LOADED=1
readonly __LIB_VALIDATION_LOADED=1