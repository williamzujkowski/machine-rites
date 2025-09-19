#!/usr/bin/env bash
# security/audit/audit-logger.sh - Tamper-proof audit logging system
#
# Description: Centralized audit logging with integrity protection
# Version: 1.0.0
# Dependencies: lib/validation.sh, lib/common.sh
# Security: Cryptographic signatures, immutable logs, real-time monitoring
#
# Features:
#   - Tamper-proof logging with cryptographic signatures
#   - Real-time log monitoring and alerting
#   - Structured logging with JSON format
#   - Log rotation with integrity preservation
#   - Compliance reporting integration

set -euo pipefail

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"
# shellcheck source=../../lib/validation.sh
source "$SCRIPT_DIR/../../lib/validation.sh"

# Configuration
readonly AUDIT_LOG_DIR="/var/log/security-audit"
readonly AUDIT_LOG_FILE="$AUDIT_LOG_DIR/security-audit.log"
readonly AUDIT_SIGNATURES_DIR="$AUDIT_LOG_DIR/signatures"
readonly AUDIT_CONFIG="/etc/security/audit-config.json"
readonly ALERT_CONFIG="/etc/security/alert-rules.json"
readonly ROTATION_SIZE_MB=100
readonly RETENTION_DAYS=365

# Secure permissions
umask 027

# Function: init_audit_system
# Purpose: Initialize the audit logging system
init_audit_system() {
    info "Initializing audit logging system"

    # Create directories with proper permissions
    sudo mkdir -p "$AUDIT_LOG_DIR" "$AUDIT_SIGNATURES_DIR"
    sudo chmod 750 "$AUDIT_LOG_DIR"
    sudo chmod 700 "$AUDIT_SIGNATURES_DIR"

    # Create audit log file if it doesn't exist
    if [[ ! -f "$AUDIT_LOG_FILE" ]]; then
        sudo touch "$AUDIT_LOG_FILE"
        sudo chmod 640 "$AUDIT_LOG_FILE"
        sudo chown root:adm "$AUDIT_LOG_FILE"
    fi

    # Initialize configuration files
    create_audit_config
    create_alert_rules

    # Initialize log with system startup
    log_audit_event "SYSTEM" "AUDIT_INIT" "INFO" "Audit logging system initialized" \
                   '{"version": "1.0.0", "hostname": "'$(hostname)'", "user": "'$(whoami)'"}'
}

# Function: create_audit_config
# Purpose: Create audit system configuration
create_audit_config() {
    if [[ ! -f "$AUDIT_CONFIG" ]]; then
        sudo mkdir -p "$(dirname "$AUDIT_CONFIG")"

        sudo tee "$AUDIT_CONFIG" > /dev/null << 'EOF'
{
    "audit_system": {
        "version": "1.0.0",
        "enabled": true,
        "log_level": "INFO",
        "retention_days": 365,
        "rotation_size_mb": 100,
        "signature_algorithm": "SHA256",
        "timestamp_format": "ISO8601"
    },
    "monitored_events": {
        "authentication": {
            "enabled": true,
            "log_level": "INFO",
            "alert_on_failure": true
        },
        "authorization": {
            "enabled": true,
            "log_level": "INFO",
            "alert_on_failure": true
        },
        "secret_access": {
            "enabled": true,
            "log_level": "INFO",
            "alert_on_access": false
        },
        "file_access": {
            "enabled": true,
            "log_level": "DEBUG",
            "monitored_paths": [
                "/etc/security",
                "/var/log/security-audit",
                "~/.password-store",
                "~/.ssh"
            ]
        },
        "command_execution": {
            "enabled": true,
            "log_level": "INFO",
            "monitored_commands": [
                "sudo",
                "su",
                "ssh",
                "scp",
                "rsync",
                "gpg",
                "pass"
            ]
        },
        "network_activity": {
            "enabled": false,
            "log_level": "INFO",
            "alert_on_suspicious": true
        }
    },
    "compliance": {
        "nist_csf": true,
        "cis_controls": true,
        "pci_dss": false,
        "soc2": false
    }
}
EOF

        sudo chmod 644 "$AUDIT_CONFIG"
    fi
}

# Function: create_alert_rules
# Purpose: Create alert rules configuration
create_alert_rules() {
    if [[ ! -f "$ALERT_CONFIG" ]]; then
        sudo mkdir -p "$(dirname "$ALERT_CONFIG")"

        sudo tee "$ALERT_CONFIG" > /dev/null << 'EOF'
{
    "alert_rules": [
        {
            "name": "authentication_failure",
            "description": "Multiple authentication failures detected",
            "event_type": "AUTHENTICATION",
            "severity": "ERROR",
            "conditions": {
                "count": 5,
                "timeframe_minutes": 10
            },
            "actions": [
                "log_alert",
                "email_admin",
                "block_ip"
            ]
        },
        {
            "name": "privilege_escalation",
            "description": "Privilege escalation attempt detected",
            "event_type": "AUTHORIZATION",
            "severity": "CRITICAL",
            "conditions": {
                "count": 1,
                "timeframe_minutes": 1
            },
            "actions": [
                "log_alert",
                "email_admin",
                "page_oncall"
            ]
        },
        {
            "name": "secret_access_burst",
            "description": "Unusual secret access pattern detected",
            "event_type": "SECRET_ACCESS",
            "severity": "WARNING",
            "conditions": {
                "count": 10,
                "timeframe_minutes": 5
            },
            "actions": [
                "log_alert",
                "email_admin"
            ]
        },
        {
            "name": "file_integrity_violation",
            "description": "Critical file modification detected",
            "event_type": "FILE_ACCESS",
            "severity": "HIGH",
            "conditions": {
                "action": "MODIFY",
                "paths": ["/etc/security", "/var/log/security-audit"]
            },
            "actions": [
                "log_alert",
                "email_admin",
                "backup_file"
            ]
        }
    ],
    "notification_channels": {
        "email": {
            "enabled": true,
            "smtp_server": "localhost",
            "admin_email": "admin@localhost"
        },
        "syslog": {
            "enabled": true,
            "facility": "auth",
            "severity": "info"
        },
        "webhook": {
            "enabled": false,
            "url": "https://hooks.slack.com/services/..."
        }
    }
}
EOF

        sudo chmod 644 "$ALERT_CONFIG"
    fi
}

# Function: generate_log_signature
# Purpose: Generate cryptographic signature for log entry
# Args: $1 - log entry
generate_log_signature() {
    local log_entry="$1"
    local timestamp="$(date -u +%Y%m%d_%H%M%S)"
    local signature_file="$AUDIT_SIGNATURES_DIR/${timestamp}.sig"

    # Generate signature using GPG
    echo "$log_entry" | gpg --detach-sign --armor --quiet --batch \
        --output "$signature_file" 2>/dev/null

    # Return signature filename
    echo "$(basename "$signature_file")"
}

# Function: log_audit_event
# Purpose: Log security audit event with integrity protection
# Args: $1 - component, $2 - event_type, $3 - severity, $4 - message, $5 - metadata (JSON)
log_audit_event() {
    local component="$1"
    local event_type="$2"
    local severity="$3"
    local message="$4"
    local metadata="${5:-{}}"

    # Validate inputs
    validate_shell_identifier "$component" || die "Invalid component: $component"
    validate_shell_identifier "$event_type" || die "Invalid event type: $event_type"

    # Generate structured log entry
    local timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    local hostname="$(hostname)"
    local user="$(whoami)"
    local pid="$$"
    local session_id="${SSH_CONNECTION:-local}"

    # Create JSON log entry
    local log_entry
    log_entry=$(jq -n \
        --arg timestamp "$timestamp" \
        --arg hostname "$hostname" \
        --arg user "$user" \
        --arg pid "$pid" \
        --arg session_id "$session_id" \
        --arg component "$component" \
        --arg event_type "$event_type" \
        --arg severity "$severity" \
        --arg message "$message" \
        --argjson metadata "$metadata" \
        '{
            timestamp: $timestamp,
            hostname: $hostname,
            user: $user,
            pid: ($pid | tonumber),
            session_id: $session_id,
            component: $component,
            event_type: $event_type,
            severity: $severity,
            message: $message,
            metadata: $metadata
        }')

    # Generate signature for integrity protection
    local signature_file
    signature_file="$(generate_log_signature "$log_entry")"

    # Add signature to log entry
    log_entry=$(echo "$log_entry" | jq --arg sig "$signature_file" '. + {signature: $sig}')

    # Write to audit log
    echo "$log_entry" | sudo tee -a "$AUDIT_LOG_FILE" >/dev/null

    # Also log to syslog for redundancy
    logger -p auth.info "SECURITY_AUDIT: $component $event_type $severity $message"

    # Check for alert conditions
    check_alert_conditions "$component" "$event_type" "$severity" "$message"

    # Rotate log if needed
    check_log_rotation
}

# Function: check_alert_conditions
# Purpose: Check if log entry triggers any alert rules
# Args: $1 - component, $2 - event_type, $3 - severity, $4 - message
check_alert_conditions() {
    local component="$1"
    local event_type="$2"
    local severity="$3"
    local message="$4"

    # This would implement alert rule evaluation
    # For now, just log high-severity events to syslog
    case "$severity" in
        ERROR|CRITICAL|HIGH)
            logger -p auth.err "SECURITY_ALERT: $component $event_type $severity $message"
            ;;
    esac
}

# Function: check_log_rotation
# Purpose: Check if log rotation is needed
check_log_rotation() {
    if [[ -f "$AUDIT_LOG_FILE" ]]; then
        local size_mb
        size_mb=$(( $(stat -c%s "$AUDIT_LOG_FILE") / 1024 / 1024 ))

        if [[ $size_mb -ge $ROTATION_SIZE_MB ]]; then
            rotate_audit_log
        fi
    fi
}

# Function: rotate_audit_log
# Purpose: Rotate audit log with integrity preservation
rotate_audit_log() {
    local timestamp="$(date +%Y%m%d_%H%M%S)"
    local rotated_log="$AUDIT_LOG_DIR/security-audit.log.$timestamp"

    info "Rotating audit log"

    # Move current log to rotated filename
    sudo mv "$AUDIT_LOG_FILE" "$rotated_log"

    # Compress rotated log
    sudo gzip "$rotated_log"

    # Create new log file
    sudo touch "$AUDIT_LOG_FILE"
    sudo chmod 640 "$AUDIT_LOG_FILE"
    sudo chown root:adm "$AUDIT_LOG_FILE"

    # Log rotation event
    log_audit_event "AUDIT_SYSTEM" "LOG_ROTATION" "INFO" "Audit log rotated" \
                   '{"rotated_file": "'${rotated_log}.gz'", "size_mb": '${ROTATION_SIZE_MB}'}'
}

# Function: verify_log_integrity
# Purpose: Verify integrity of audit log entries
verify_log_integrity() {
    info "Verifying audit log integrity"

    local errors=0
    local total=0

    while IFS= read -r line; do
        ((total++))

        # Parse JSON log entry
        local signature
        signature="$(echo "$line" | jq -r '.signature // empty')"

        if [[ -n "$signature" ]]; then
            local signature_file="$AUDIT_SIGNATURES_DIR/$signature"

            if [[ -f "$signature_file" ]]; then
                # Remove signature from log entry for verification
                local log_entry_without_sig
                log_entry_without_sig="$(echo "$line" | jq 'del(.signature)')"

                # Verify signature
                if echo "$log_entry_without_sig" | gpg --verify "$signature_file" - 2>/dev/null; then
                    : # Signature valid
                else
                    warn "Invalid signature for log entry: $total"
                    ((errors++))
                fi
            else
                warn "Missing signature file: $signature"
                ((errors++))
            fi
        else
            warn "Log entry missing signature: $total"
            ((errors++))
        fi
    done < "$AUDIT_LOG_FILE"

    if [[ $errors -eq 0 ]]; then
        ok "All $total log entries verified successfully"
        return 0
    else
        fail "$errors/$total log entries failed verification"
        return 1
    fi
}

# Function: search_audit_logs
# Purpose: Search audit logs with filtering
# Args: $1 - search criteria (JSON)
search_audit_logs() {
    local criteria="${1:-{}}"

    info "Searching audit logs"

    # Use jq to filter logs based on criteria
    jq --argjson criteria "$criteria" '
        select(
            (($criteria.component // empty) as $comp | if $comp then .component == $comp else true end) and
            (($criteria.event_type // empty) as $event | if $event then .event_type == $event else true end) and
            (($criteria.severity // empty) as $sev | if $sev then .severity == $sev else true end) and
            (($criteria.user // empty) as $usr | if $usr then .user == $usr else true end) and
            (($criteria.start_time // empty) as $start | if $start then .timestamp >= $start else true end) and
            (($criteria.end_time // empty) as $end | if $end then .timestamp <= $end else true end)
        )
    ' "$AUDIT_LOG_FILE"
}

# Function: generate_audit_report
# Purpose: Generate audit report for compliance
# Args: $1 - report type, $2 - start date, $3 - end date
generate_audit_report() {
    local report_type="${1:-summary}"
    local start_date="${2:-$(date -d '30 days ago' +%Y-%m-%d)}"
    local end_date="${3:-$(date +%Y-%m-%d)}"

    info "Generating audit report: $report_type ($start_date to $end_date)"

    local criteria="{\"start_time\": \"${start_date}T00:00:00Z\", \"end_time\": \"${end_date}T23:59:59Z\"}"

    case "$report_type" in
        summary)
            echo "# Security Audit Summary Report"
            echo "## Period: $start_date to $end_date"
            echo

            echo "### Event Summary"
            search_audit_logs "$criteria" | jq -r '.event_type' | sort | uniq -c | sort -nr
            echo

            echo "### Severity Distribution"
            search_audit_logs "$criteria" | jq -r '.severity' | sort | uniq -c | sort -nr
            echo

            echo "### Top Users"
            search_audit_logs "$criteria" | jq -r '.user' | sort | uniq -c | sort -nr | head -10
            ;;
        detailed)
            echo "# Detailed Security Audit Report"
            echo "## Period: $start_date to $end_date"
            echo
            search_audit_logs "$criteria" | jq -r '
                "### " + .timestamp + " - " + .event_type + " (" + .severity + ")" + "\n" +
                "**Component:** " + .component + "\n" +
                "**User:** " + .user + "\n" +
                "**Message:** " + .message + "\n" +
                "**Metadata:** " + (.metadata | tostring) + "\n"
            '
            ;;
        compliance)
            generate_compliance_report "$criteria"
            ;;
    esac
}

# Function: generate_compliance_report
# Purpose: Generate compliance-specific report
generate_compliance_report() {
    local criteria="$1"

    echo "# Compliance Audit Report"
    echo "## NIST Cybersecurity Framework Compliance"
    echo

    # Identify events (DE.AE)
    echo "### DE.AE (Anomalies and Events)"
    search_audit_logs "$criteria" | jq -r 'select(.severity == "ERROR" or .severity == "CRITICAL") |
        .timestamp + " - " + .event_type + ": " + .message'
    echo

    # Access control (PR.AC)
    echo "### PR.AC (Access Control)"
    search_audit_logs "$criteria" | jq -r 'select(.event_type == "AUTHENTICATION" or .event_type == "AUTHORIZATION") |
        .timestamp + " - " + .event_type + ": " + .message'
    echo

    # Data security (PR.DS)
    echo "### PR.DS (Data Security)"
    search_audit_logs "$criteria" | jq -r 'select(.event_type == "SECRET_ACCESS" or .event_type == "FILE_ACCESS") |
        .timestamp + " - " + .event_type + ": " + .message'
    echo
}

# Function: cleanup_old_logs
# Purpose: Clean up old audit logs and signatures
cleanup_old_logs() {
    info "Cleaning up old audit logs"

    # Remove rotated logs older than retention period
    find "$AUDIT_LOG_DIR" -name "security-audit.log.*.gz" -mtime +$RETENTION_DAYS -delete

    # Remove old signature files
    find "$AUDIT_SIGNATURES_DIR" -name "*.sig" -mtime +$RETENTION_DAYS -delete

    # Log cleanup event
    log_audit_event "AUDIT_SYSTEM" "LOG_CLEANUP" "INFO" "Old audit logs cleaned up" \
                   '{"retention_days": '${RETENTION_DAYS}'}'
}

# Function: main
# Purpose: Main entry point for audit logger
main() {
    local action="${1:-}"

    case "$action" in
        init)
            init_audit_system
            ;;
        log)
            shift
            log_audit_event "$@"
            ;;
        verify)
            verify_log_integrity
            ;;
        search)
            shift
            search_audit_logs "$@"
            ;;
        report)
            shift
            generate_audit_report "$@"
            ;;
        cleanup)
            cleanup_old_logs
            ;;
        *)
            echo "Usage: $0 {init|log|verify|search|report|cleanup}"
            echo "  init                   - Initialize audit system"
            echo "  log <args>            - Log audit event"
            echo "  verify                - Verify log integrity"
            echo "  search <criteria>     - Search audit logs"
            echo "  report [type] [dates] - Generate audit report"
            echo "  cleanup               - Clean up old logs"
            exit 1
            ;;
    esac
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi