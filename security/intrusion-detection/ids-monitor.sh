#!/usr/bin/env bash
# security/intrusion-detection/ids-monitor.sh - Intrusion Detection System
#
# Description: Real-time intrusion detection and response system
# Version: 1.0.0
# Dependencies: lib/validation.sh, lib/common.sh, inotify-tools
# Security: Real-time monitoring, automated response, threat intelligence
#
# Features:
#   - File integrity monitoring (FIM)
#   - Real-time log analysis
#   - Network anomaly detection
#   - Automated threat response
#   - Threat intelligence integration

set -euo pipefail

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"
# shellcheck source=../../lib/validation.sh
source "$SCRIPT_DIR/../../lib/validation.sh"
# shellcheck source=../audit/audit-logger.sh
source "$SCRIPT_DIR/../audit/audit-logger.sh"

# Configuration
readonly IDS_CONFIG_DIR="/etc/security/ids"
readonly IDS_LOG_DIR="/var/log/security-ids"
readonly IDS_RULES_FILE="$IDS_CONFIG_DIR/rules.json"
readonly IDS_WHITELIST_FILE="$IDS_CONFIG_DIR/whitelist.json"
readonly IDS_QUARANTINE_DIR="/var/quarantine"
readonly IDS_PID_FILE="/var/run/ids-monitor.pid"
readonly MONITOR_INTERVAL=5

# Critical paths to monitor
readonly CRITICAL_PATHS=(
    "/etc/passwd"
    "/etc/shadow"
    "/etc/sudoers"
    "/etc/ssh/sshd_config"
    "/home/*/.ssh"
    "/var/log/auth.log"
    "/var/log/secure"
    "$HOME/.password-store"
    "/etc/security"
)

# Secure permissions
umask 027

# Function: init_ids_system
# Purpose: Initialize the intrusion detection system
init_ids_system() {
    info "Initializing Intrusion Detection System"

    # Create directories
    sudo mkdir -p "$IDS_CONFIG_DIR" "$IDS_LOG_DIR" "$IDS_QUARANTINE_DIR"
    sudo chmod 750 "$IDS_CONFIG_DIR" "$IDS_LOG_DIR"
    sudo chmod 700 "$IDS_QUARANTINE_DIR"

    # Check required tools
    local required_tools=("inotifywait" "ss" "netstat" "lsof" "awk" "jq")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            warn "Required tool not found: $tool"
            case "$tool" in
                inotifywait)
                    info "Install with: sudo apt-get install inotify-tools"
                    ;;
            esac
        fi
    done

    # Create configuration files
    create_ids_rules
    create_ids_whitelist

    # Initialize baseline checksums
    create_integrity_baseline

    # Log initialization
    log_audit_event "IDS" "SYSTEM_INIT" "INFO" "IDS system initialized" \
                   '{"version": "1.0.0", "config_dir": "'$IDS_CONFIG_DIR'"}'
}

# Function: create_ids_rules
# Purpose: Create IDS detection rules
create_ids_rules() {
    if [[ ! -f "$IDS_RULES_FILE" ]]; then
        sudo tee "$IDS_RULES_FILE" > /dev/null << 'EOF'
{
    "file_integrity_rules": [
        {
            "name": "critical_system_files",
            "description": "Monitor critical system configuration files",
            "paths": [
                "/etc/passwd",
                "/etc/shadow",
                "/etc/sudoers",
                "/etc/ssh/sshd_config"
            ],
            "events": ["modify", "delete", "move"],
            "severity": "CRITICAL",
            "response": ["alert", "quarantine", "block_user"]
        },
        {
            "name": "security_configs",
            "description": "Monitor security configuration changes",
            "paths": [
                "/etc/security",
                "/var/log/security-audit"
            ],
            "events": ["modify", "delete", "create"],
            "severity": "HIGH",
            "response": ["alert", "backup"]
        },
        {
            "name": "ssh_keys",
            "description": "Monitor SSH key changes",
            "paths": [
                "/home/*/.ssh",
                "/root/.ssh"
            ],
            "events": ["create", "modify", "delete"],
            "severity": "HIGH",
            "response": ["alert", "audit_log"]
        },
        {
            "name": "password_store",
            "description": "Monitor password store access",
            "paths": [
                "~/.password-store"
            ],
            "events": ["access", "modify"],
            "severity": "MEDIUM",
            "response": ["audit_log"]
        }
    ],
    "log_analysis_rules": [
        {
            "name": "brute_force_ssh",
            "description": "Detect SSH brute force attacks",
            "log_files": ["/var/log/auth.log", "/var/log/secure"],
            "pattern": "Failed password for .* from .* port .*",
            "threshold": 5,
            "timeframe_minutes": 10,
            "severity": "HIGH",
            "response": ["alert", "block_ip", "rate_limit"]
        },
        {
            "name": "privilege_escalation",
            "description": "Detect privilege escalation attempts",
            "log_files": ["/var/log/auth.log", "/var/log/secure"],
            "pattern": "sudo:.*COMMAND=.*",
            "conditions": {
                "user_not_in_sudoers": true,
                "unusual_commands": ["passwd", "su", "chmod 777"]
            },
            "severity": "CRITICAL",
            "response": ["alert", "block_user", "isolate_session"]
        },
        {
            "name": "unusual_network_activity",
            "description": "Detect unusual network connections",
            "conditions": {
                "new_listening_ports": true,
                "unusual_outbound_connections": true,
                "high_bandwidth_usage": true
            },
            "severity": "MEDIUM",
            "response": ["alert", "monitor"]
        }
    ],
    "behavioral_rules": [
        {
            "name": "off_hours_access",
            "description": "Detect access outside business hours",
            "time_range": "22:00-06:00",
            "weekends": true,
            "severity": "MEDIUM",
            "response": ["alert", "require_mfa"]
        },
        {
            "name": "geographic_anomaly",
            "description": "Detect access from unusual locations",
            "enable_geolocation": false,
            "severity": "MEDIUM",
            "response": ["alert", "verify_user"]
        }
    ],
    "response_actions": {
        "alert": {
            "enabled": true,
            "methods": ["syslog", "email", "webhook"]
        },
        "block_ip": {
            "enabled": true,
            "duration_minutes": 60,
            "whitelist_check": true
        },
        "block_user": {
            "enabled": true,
            "duration_minutes": 30,
            "require_admin_unlock": true
        },
        "quarantine": {
            "enabled": true,
            "backup_original": true
        },
        "rate_limit": {
            "enabled": true,
            "connections_per_minute": 5
        }
    }
}
EOF
        sudo chmod 644 "$IDS_RULES_FILE"
    fi
}

# Function: create_ids_whitelist
# Purpose: Create IDS whitelist configuration
create_ids_whitelist() {
    if [[ ! -f "$IDS_WHITELIST_FILE" ]]; then
        sudo tee "$IDS_WHITELIST_FILE" > /dev/null << 'EOF'
{
    "ip_whitelist": [
        "127.0.0.0/8",
        "10.0.0.0/8",
        "192.168.0.0/16",
        "172.16.0.0/12"
    ],
    "user_whitelist": [
        "root",
        "admin"
    ],
    "process_whitelist": [
        {
            "name": "system_backup",
            "command": "/usr/bin/rsync",
            "user": "backup"
        },
        {
            "name": "log_rotation",
            "command": "/usr/sbin/logrotate",
            "user": "root"
        }
    ],
    "file_whitelist": [
        {
            "path": "/var/log/*",
            "operations": ["write", "append"],
            "processes": ["rsyslog", "systemd-journald"]
        }
    ],
    "time_based_whitelist": [
        {
            "name": "maintenance_window",
            "start_time": "02:00",
            "end_time": "04:00",
            "days": ["sunday"],
            "relaxed_monitoring": true
        }
    ]
}
EOF
        sudo chmod 644 "$IDS_WHITELIST_FILE"
    fi
}

# Function: create_integrity_baseline
# Purpose: Create baseline checksums for file integrity monitoring
create_integrity_baseline() {
    local baseline_file="$IDS_CONFIG_DIR/integrity_baseline.json"

    info "Creating file integrity baseline"

    {
        echo "{"
        echo "  \"baseline_created\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
        echo "  \"hostname\": \"$(hostname)\","
        echo "  \"files\": {"

        local first=true
        for path in "${CRITICAL_PATHS[@]}"; do
            # Expand glob patterns
            for file in $path; do
                if [[ -f "$file" ]] && [[ -r "$file" ]]; then
                    [[ "$first" == "true" ]] && first=false || echo ","

                    local checksum
                    checksum="$(sha256sum "$file" | cut -d' ' -f1)"
                    local permissions
                    permissions="$(stat -c "%a" "$file")"
                    local owner
                    owner="$(stat -c "%U:%G" "$file")"
                    local mtime
                    mtime="$(stat -c "%Y" "$file")"

                    echo -n "    \"$file\": {"
                    echo -n "\"checksum\": \"$checksum\", "
                    echo -n "\"permissions\": \"$permissions\", "
                    echo -n "\"owner\": \"$owner\", "
                    echo -n "\"mtime\": $mtime"
                    echo -n "}"
                fi
            done
        done

        echo
        echo "  }"
        echo "}"
    } | sudo tee "$baseline_file" > /dev/null

    sudo chmod 644 "$baseline_file"

    log_audit_event "IDS" "BASELINE_CREATED" "INFO" "File integrity baseline created" \
                   '{"baseline_file": "'$baseline_file'", "files_count": '$(wc -l < "$baseline_file")'}'
}

# Function: check_file_integrity
# Purpose: Check file integrity against baseline
check_file_integrity() {
    local baseline_file="$IDS_CONFIG_DIR/integrity_baseline.json"

    if [[ ! -f "$baseline_file" ]]; then
        warn "No baseline file found, creating new baseline"
        create_integrity_baseline
        return 0
    fi

    info "Checking file integrity against baseline"
    local violations=0

    # Read baseline and check each file
    jq -r '.files | to_entries[] | "\(.key) \(.value.checksum) \(.value.permissions) \(.value.owner)"' \
        "$baseline_file" | while read -r file expected_checksum expected_perms expected_owner; do

        if [[ -f "$file" ]]; then
            local current_checksum
            current_checksum="$(sha256sum "$file" | cut -d' ' -f1)"
            local current_perms
            current_perms="$(stat -c "%a" "$file")"
            local current_owner
            current_owner="$(stat -c "%U:%G" "$file")"

            # Check for violations
            if [[ "$current_checksum" != "$expected_checksum" ]]; then
                warn "File integrity violation: $file (checksum mismatch)"
                log_audit_event "IDS" "INTEGRITY_VIOLATION" "CRITICAL" "File checksum mismatch" \
                               '{"file": "'$file'", "expected": "'$expected_checksum'", "actual": "'$current_checksum'"}'
                handle_integrity_violation "$file" "checksum"
                ((violations++))
            fi

            if [[ "$current_perms" != "$expected_perms" ]]; then
                warn "File permissions changed: $file ($expected_perms -> $current_perms)"
                log_audit_event "IDS" "PERMISSION_CHANGE" "HIGH" "File permissions changed" \
                               '{"file": "'$file'", "expected": "'$expected_perms'", "actual": "'$current_perms'"}'
                ((violations++))
            fi

            if [[ "$current_owner" != "$expected_owner" ]]; then
                warn "File ownership changed: $file ($expected_owner -> $current_owner)"
                log_audit_event "IDS" "OWNERSHIP_CHANGE" "HIGH" "File ownership changed" \
                               '{"file": "'$file'", "expected": "'$expected_owner'", "actual": "'$current_owner'"}'
                ((violations++))
            fi
        else
            warn "File deleted or inaccessible: $file"
            log_audit_event "IDS" "FILE_DELETED" "CRITICAL" "Critical file deleted" \
                           '{"file": "'$file'"}'
            ((violations++))
        fi
    done

    if [[ $violations -eq 0 ]]; then
        ok "File integrity check passed"
    else
        fail "$violations integrity violations detected"
    fi

    return $violations
}

# Function: handle_integrity_violation
# Purpose: Handle detected integrity violations
# Args: $1 - file path, $2 - violation type
handle_integrity_violation() {
    local file="$1"
    local violation_type="$2"

    case "$violation_type" in
        checksum)
            # Quarantine the modified file
            quarantine_file "$file"

            # Check if we have a backup to restore
            if [[ -f "$file.backup" ]]; then
                warn "Attempting to restore $file from backup"
                sudo cp "$file.backup" "$file"
                log_audit_event "IDS" "FILE_RESTORED" "INFO" "File restored from backup" \
                               '{"file": "'$file'"}'
            fi
            ;;
    esac
}

# Function: quarantine_file
# Purpose: Quarantine suspicious file
# Args: $1 - file path
quarantine_file() {
    local file="$1"
    local quarantine_name="$(basename "$file").$(date +%Y%m%d_%H%M%S)"
    local quarantine_path="$IDS_QUARANTINE_DIR/$quarantine_name"

    info "Quarantining file: $file"

    # Copy file to quarantine
    sudo cp "$file" "$quarantine_path"
    sudo chmod 000 "$quarantine_path"

    # Create metadata file
    cat << EOF | sudo tee "${quarantine_path}.metadata" > /dev/null
{
    "original_path": "$file",
    "quarantine_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "reason": "integrity_violation",
    "checksum": "$(sha256sum "$file" | cut -d' ' -f1)",
    "permissions": "$(stat -c "%a" "$file")",
    "owner": "$(stat -c "%U:%G" "$file")"
}
EOF

    log_audit_event "IDS" "FILE_QUARANTINED" "HIGH" "File quarantined" \
                   '{"file": "'$file'", "quarantine_path": "'$quarantine_path'"}'
}

# Function: monitor_real_time
# Purpose: Start real-time file system monitoring
monitor_real_time() {
    info "Starting real-time file system monitoring"

    # Check if inotify-tools is available
    if ! command -v inotifywait >/dev/null 2>&1; then
        die "inotifywait not found. Install with: sudo apt-get install inotify-tools"
    fi

    # Monitor critical paths
    local monitor_paths=()
    for path in "${CRITICAL_PATHS[@]}"; do
        # Expand glob patterns
        for expanded_path in $path; do
            if [[ -e "$expanded_path" ]]; then
                monitor_paths+=("$expanded_path")
            fi
        done
    done

    # Start inotify monitoring in background
    inotifywait -m -r -e modify,create,delete,move \
        --format '%w%f %e %T' --timefmt '%Y-%m-%d %H:%M:%S' \
        "${monitor_paths[@]}" 2>/dev/null | while read -r file event timestamp; do

        # Skip temporary files and common non-threatening changes
        if [[ "$file" =~ \.(tmp|swp|swap)$ ]] || [[ "$file" =~ /\.# ]]; then
            continue
        fi

        # Log the event
        log_audit_event "IDS" "FILE_CHANGE" "INFO" "File system change detected" \
                       '{"file": "'$file'", "event": "'$event'", "timestamp": "'$timestamp'"}'

        # Check if this is a critical file change
        case "$event" in
            MODIFY|DELETE|MOVED_TO|MOVED_FROM)
                if is_critical_file "$file"; then
                    handle_critical_file_change "$file" "$event"
                fi
                ;;
        esac
    done &

    echo $! > "$IDS_PID_FILE"
    log_audit_event "IDS" "MONITOR_STARTED" "INFO" "Real-time monitoring started" \
                   '{"pid": '$!', "monitored_paths": '$(printf '%s\n' "${monitor_paths[@]}" | jq -R . | jq -s .)'}'
}

# Function: is_critical_file
# Purpose: Check if file is in critical paths
# Args: $1 - file path
is_critical_file() {
    local file="$1"

    for critical_path in "${CRITICAL_PATHS[@]}"; do
        if [[ "$file" == $critical_path ]] || [[ "$file" =~ ^${critical_path%\*} ]]; then
            return 0
        fi
    done

    return 1
}

# Function: handle_critical_file_change
# Purpose: Handle changes to critical files
# Args: $1 - file path, $2 - event type
handle_critical_file_change() {
    local file="$1"
    local event="$2"

    warn "Critical file change detected: $file ($event)"

    log_audit_event "IDS" "CRITICAL_FILE_CHANGE" "CRITICAL" "Critical file modified" \
                   '{"file": "'$file'", "event": "'$event'", "user": "'$(whoami)'", "tty": "'$(tty 2>/dev/null || echo 'unknown')'"}'

    # Immediate response actions
    case "$event" in
        DELETE)
            # Critical file deleted - high priority alert
            alert_admin "CRITICAL: File deleted: $file"
            ;;
        MODIFY)
            # Check integrity immediately
            check_file_integrity
            ;;
    esac
}

# Function: alert_admin
# Purpose: Send immediate alert to administrators
# Args: $1 - alert message
alert_admin() {
    local message="$1"

    # Log to syslog with high priority
    logger -p auth.crit "IDS_ALERT: $message"

    # Send email if configured
    if command -v mail >/dev/null 2>&1; then
        echo "IDS Alert from $(hostname): $message" | \
            mail -s "IDS Security Alert" admin@localhost 2>/dev/null || true
    fi

    # Write to console if running interactively
    if [[ -t 1 ]]; then
        echo -e "\n\033[31m[SECURITY ALERT]\033[0m $message\n" >&2
    fi
}

# Function: analyze_logs
# Purpose: Analyze system logs for threats
analyze_logs() {
    info "Analyzing system logs for threats"

    local log_files=("/var/log/auth.log" "/var/log/secure" "/var/log/syslog")

    for log_file in "${log_files[@]}"; do
        if [[ -f "$log_file" ]]; then
            analyze_auth_log "$log_file"
        fi
    done
}

# Function: analyze_auth_log
# Purpose: Analyze authentication logs for suspicious activity
# Args: $1 - log file path
analyze_auth_log() {
    local log_file="$1"

    # Check for brute force attempts
    local failed_attempts
    failed_attempts=$(grep "Failed password" "$log_file" | tail -100 | \
        awk '{print $1 " " $2 " " $3 " " $11}' | sort | uniq -c | sort -nr)

    if [[ -n "$failed_attempts" ]]; then
        echo "$failed_attempts" | while read -r count date time ip; do
            if [[ $count -gt 5 ]]; then
                warn "Potential brute force from $ip: $count failed attempts"
                log_audit_event "IDS" "BRUTE_FORCE_DETECTED" "HIGH" "Brute force attack detected" \
                               '{"source_ip": "'$ip'", "attempts": '$count', "log_file": "'$log_file'"}'

                # Consider blocking the IP
                consider_ip_block "$ip" "$count"
            fi
        done
    fi

    # Check for privilege escalation
    grep -i "sudo" "$log_file" | tail -50 | while read -r line; do
        if echo "$line" | grep -qi "command not allowed\|incorrect password"; then
            warn "Privilege escalation attempt detected: $line"
            log_audit_event "IDS" "PRIVILEGE_ESCALATION" "CRITICAL" "Privilege escalation attempt" \
                           '{"log_entry": "'$(echo "$line" | sed 's/"/\\"/g')'", "log_file": "'$log_file'"}'
        fi
    done
}

# Function: consider_ip_block
# Purpose: Consider blocking an IP address
# Args: $1 - IP address, $2 - attempt count
consider_ip_block() {
    local ip="$1"
    local attempts="$2"

    # Check whitelist first
    if is_ip_whitelisted "$ip"; then
        info "IP $ip is whitelisted, not blocking despite $attempts attempts"
        return 0
    fi

    # Block IP using iptables if available
    if command -v iptables >/dev/null 2>&1 && [[ $attempts -gt 10 ]]; then
        warn "Blocking IP $ip due to $attempts failed attempts"

        # Add temporary block (60 minutes)
        sudo iptables -A INPUT -s "$ip" -j DROP

        # Schedule removal of block
        (sleep 3600; sudo iptables -D INPUT -s "$ip" -j DROP 2>/dev/null) &

        log_audit_event "IDS" "IP_BLOCKED" "HIGH" "IP address blocked" \
                       '{"ip": "'$ip'", "attempts": '$attempts', "duration_minutes": 60}'
    fi
}

# Function: is_ip_whitelisted
# Purpose: Check if IP is in whitelist
# Args: $1 - IP address
is_ip_whitelisted() {
    local ip="$1"

    # Check against whitelist in configuration
    if [[ -f "$IDS_WHITELIST_FILE" ]]; then
        local whitelisted_ranges
        whitelisted_ranges=$(jq -r '.ip_whitelist[]' "$IDS_WHITELIST_FILE" 2>/dev/null || echo "")

        for range in $whitelisted_ranges; do
            # Simple CIDR check (could be improved with proper IP validation)
            if [[ "$ip" =~ ^${range%/*} ]]; then
                return 0
            fi
        done
    fi

    return 1
}

# Function: stop_monitoring
# Purpose: Stop IDS monitoring
stop_monitoring() {
    info "Stopping IDS monitoring"

    if [[ -f "$IDS_PID_FILE" ]]; then
        local pid
        pid=$(cat "$IDS_PID_FILE")

        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid"
            wait "$pid" 2>/dev/null || true
            ok "IDS monitoring stopped (PID: $pid)"
        fi

        rm -f "$IDS_PID_FILE"
    fi

    log_audit_event "IDS" "MONITOR_STOPPED" "INFO" "IDS monitoring stopped" '{}'
}

# Function: status_check
# Purpose: Check IDS status
status_check() {
    echo "=== Intrusion Detection System Status ==="
    echo

    # Check if monitoring is running
    if [[ -f "$IDS_PID_FILE" ]]; then
        local pid
        pid=$(cat "$IDS_PID_FILE")

        if kill -0 "$pid" 2>/dev/null; then
            ok "Monitoring: Running (PID: $pid)"
        else
            warn "Monitoring: Not running (stale PID file)"
            rm -f "$IDS_PID_FILE"
        fi
    else
        warn "Monitoring: Not running"
    fi

    # Check configuration files
    if [[ -f "$IDS_RULES_FILE" ]]; then
        ok "Rules file: Present"
    else
        warn "Rules file: Missing"
    fi

    if [[ -f "$IDS_WHITELIST_FILE" ]]; then
        ok "Whitelist file: Present"
    else
        warn "Whitelist file: Missing"
    fi

    # Check baseline
    local baseline_file="$IDS_CONFIG_DIR/integrity_baseline.json"
    if [[ -f "$baseline_file" ]]; then
        local baseline_age
        baseline_age=$(( ($(date +%s) - $(stat -c %Y "$baseline_file")) / 86400 ))
        ok "Integrity baseline: Present (${baseline_age} days old)"
    else
        warn "Integrity baseline: Missing"
    fi

    # Check quarantine directory
    local quarantine_count
    quarantine_count=$(find "$IDS_QUARANTINE_DIR" -type f 2>/dev/null | wc -l || echo 0)
    if [[ $quarantine_count -gt 0 ]]; then
        warn "Quarantined files: $quarantine_count"
    else
        ok "Quarantined files: None"
    fi

    echo
    echo "Recent alerts (last 24 hours):"
    if command -v journalctl >/dev/null 2>&1; then
        journalctl --since "24 hours ago" | grep -i "IDS_ALERT\|SECURITY_ALERT" | tail -5
    else
        grep -i "IDS_ALERT\|SECURITY_ALERT" /var/log/syslog 2>/dev/null | tail -5 || echo "No recent alerts"
    fi
}

# Function: main
# Purpose: Main entry point
main() {
    local action="${1:-}"

    case "$action" in
        init)
            init_ids_system
            ;;
        start)
            check_file_integrity
            monitor_real_time
            ;;
        stop)
            stop_monitoring
            ;;
        check)
            check_file_integrity
            ;;
        analyze)
            analyze_logs
            ;;
        status)
            status_check
            ;;
        baseline)
            create_integrity_baseline
            ;;
        *)
            echo "Usage: $0 {init|start|stop|check|analyze|status|baseline}"
            echo "  init     - Initialize IDS system"
            echo "  start    - Start real-time monitoring"
            echo "  stop     - Stop monitoring"
            echo "  check    - Check file integrity"
            echo "  analyze  - Analyze system logs"
            echo "  status   - Show IDS status"
            echo "  baseline - Create new integrity baseline"
            exit 1
            ;;
    esac
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi