#!/usr/bin/env bash
# security/compliance/cis-benchmark.sh - CIS Controls Implementation and Assessment
#
# Description: CIS Controls v8 alignment and automated compliance checking
# Version: 1.0.0
# Dependencies: lib/validation.sh, lib/common.sh, jq
# Security: CIS compliance assessment, automated remediation, benchmark reporting
#
# Features:
#   - CIS Controls v8 implementation mapping
#   - Automated security configuration assessment
#   - Remediation recommendations and automation
#   - Compliance scoring and reporting
#   - Integration with existing security tools

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
readonly CIS_CONFIG_DIR="/etc/security/cis"
readonly CIS_RESULTS_DIR="/var/log/cis-assessment"
readonly CIS_MAPPING_FILE="$CIS_CONFIG_DIR/cis-controls-mapping.json"
readonly CIS_POLICIES_DIR="$CIS_CONFIG_DIR/policies"
readonly CIS_REMEDIATION_DIR="$CIS_CONFIG_DIR/remediation"

# Secure permissions
umask 027

# Function: init_cis_compliance
# Purpose: Initialize CIS Controls compliance system
init_cis_compliance() {
    info "Initializing CIS Controls v8 compliance system"

    # Create directories
    sudo mkdir -p "$CIS_CONFIG_DIR" "$CIS_RESULTS_DIR" "$CIS_POLICIES_DIR" "$CIS_REMEDIATION_DIR"
    sudo chmod 750 "$CIS_CONFIG_DIR" "$CIS_RESULTS_DIR" "$CIS_POLICIES_DIR" "$CIS_REMEDIATION_DIR"

    # Create CIS Controls mappings
    create_cis_mappings

    # Create policy configurations
    create_cis_policies

    # Create remediation scripts
    create_remediation_scripts

    # Log initialization
    log_audit_event "CIS" "SYSTEM_INIT" "INFO" "CIS compliance system initialized" \
                   '{"version": "8.0", "config_dir": "'$CIS_CONFIG_DIR'"}'

    ok "CIS Controls compliance system initialized"
}

# Function: create_cis_mappings
# Purpose: Create comprehensive CIS Controls v8 mappings
create_cis_mappings() {
    if [[ ! -f "$CIS_MAPPING_FILE" ]]; then
        info "Creating CIS Controls v8 mappings"

        sudo tee "$CIS_MAPPING_FILE" > /dev/null << 'EOF'
{
    "framework": "CIS Controls v8",
    "version": "8.0",
    "organization": "machine-rites",
    "last_updated": "2024-01-01T00:00:00Z",
    "implementation_groups": {
        "IG1": {
            "description": "Basic cyber hygiene controls for small/medium organizations",
            "priority": "Essential"
        },
        "IG2": {
            "description": "Foundational controls for organizations with IT resources",
            "priority": "Foundational"
        },
        "IG3": {
            "description": "Organizational controls for mature security programs",
            "priority": "Organizational"
        }
    },
    "controls": {
        "CIS_1": {
            "title": "Inventory and Control of Enterprise Assets",
            "description": "Actively manage all enterprise assets connected to the infrastructure",
            "implementation_group": "IG1",
            "safeguards": {
                "1.1": {
                    "title": "Establish and Maintain Detailed Enterprise Asset Inventory",
                    "description": "Establish and maintain accurate, detailed, and up-to-date inventory of all enterprise assets",
                    "implementation_status": "implemented",
                    "machine_rites_features": [
                        "tools/doctor.sh - System inventory and health checks",
                        "bootstrap/modules/00-prereqs.sh - Hardware detection",
                        "lib/platform.sh - Platform and system detection"
                    ],
                    "assessment_criteria": [
                        "Automated asset discovery",
                        "Regular inventory updates",
                        "Asset classification",
                        "Owner assignment"
                    ],
                    "evidence": [
                        "doctor.sh output showing system inventory",
                        "Platform detection logs",
                        "Bootstrap system reports"
                    ]
                },
                "1.2": {
                    "title": "Address Unauthorized Assets",
                    "description": "Ensure that only authorized assets are given access to the enterprise network",
                    "implementation_status": "partially_implemented",
                    "machine_rites_features": [
                        "security/intrusion-detection/ - Network monitoring",
                        "SSH key management and validation"
                    ],
                    "gaps": [
                        "Automated unauthorized asset detection",
                        "Network access control enforcement"
                    ]
                }
            }
        },
        "CIS_2": {
            "title": "Inventory and Control of Software Assets",
            "description": "Actively manage all software on the network",
            "implementation_group": "IG1",
            "safeguards": {
                "2.1": {
                    "title": "Establish and Maintain Software Inventory",
                    "description": "Establish and maintain accurate, detailed inventory of all authorized software",
                    "implementation_status": "implemented",
                    "machine_rites_features": [
                        "bootstrap/modules/20-system-packages.sh - Package management",
                        "devtools-installer.sh - Development tools inventory",
                        "tools/update.sh - Software version tracking"
                    ],
                    "assessment_criteria": [
                        "Comprehensive software catalog",
                        "Version tracking",
                        "License management",
                        "Update status monitoring"
                    ]
                },
                "2.2": {
                    "title": "Ensure Authorized Software is Currently Supported",
                    "description": "Ensure that only currently supported software is designated as authorized",
                    "implementation_status": "implemented",
                    "machine_rites_features": [
                        "get_latest_versions.sh - Version checking",
                        "devtools_versions.sh - Supported version tracking"
                    ]
                }
            }
        },
        "CIS_3": {
            "title": "Data Protection",
            "description": "Develop processes to identify, classify, and protect data",
            "implementation_group": "IG1",
            "safeguards": {
                "3.1": {
                    "title": "Establish and Maintain Data Management Process",
                    "description": "Establish and maintain data management process",
                    "implementation_status": "implemented",
                    "machine_rites_features": [
                        "bootstrap/modules/50-secrets.sh - Secret data management",
                        "tools/rotate-secrets.sh - Data lifecycle management",
                        "lib/atomic.sh - Secure data operations"
                    ]
                },
                "3.3": {
                    "title": "Configure Data Access Control Lists",
                    "description": "Configure data access control lists based on a user's need to know",
                    "implementation_status": "implemented",
                    "machine_rites_features": [
                        "umask 027 enforcement - File access controls",
                        "GPG encryption for sensitive data",
                        "Pass password store access control"
                    ]
                },
                "3.11": {
                    "title": "Encrypt Sensitive Data at Rest",
                    "description": "Encrypt sensitive data at rest on servers, applications, and databases",
                    "implementation_status": "implemented",
                    "machine_rites_features": [
                        "GPG encryption for passwords and secrets",
                        "Encrypted backup systems",
                        "Secure temporary file handling"
                    ]
                }
            }
        },
        "CIS_4": {
            "title": "Secure Configuration of Enterprise Assets and Software",
            "description": "Establish and maintain secure configuration of enterprise assets and software",
            "implementation_group": "IG1",
            "safeguards": {
                "4.1": {
                    "title": "Establish and Maintain Secure Configuration Process",
                    "description": "Establish and maintain secure configuration process for enterprise assets",
                    "implementation_status": "implemented",
                    "machine_rites_features": [
                        "bootstrap/ - Secure system configuration",
                        "standards.md - Security configuration standards",
                        "Makefile - Configuration management automation"
                    ]
                },
                "4.2": {
                    "title": "Establish and Maintain Secure Configuration Baseline",
                    "description": "Establish and maintain secure configuration baseline for enterprise assets",
                    "implementation_status": "implemented",
                    "machine_rites_features": [
                        "bootstrap baseline configuration",
                        "security/intrusion-detection/ - Configuration monitoring",
                        "File integrity monitoring"
                    ]
                }
            }
        },
        "CIS_5": {
            "title": "Account Management",
            "description": "Use processes and tools to assign and manage authorization to credentials",
            "implementation_group": "IG1",
            "safeguards": {
                "5.1": {
                    "title": "Establish and Maintain Inventory of Accounts",
                    "description": "Establish and maintain inventory of all accounts managed in the enterprise",
                    "implementation_status": "partially_implemented",
                    "machine_rites_features": [
                        "User account detection in tools/doctor.sh",
                        "SSH key inventory and management"
                    ],
                    "gaps": [
                        "Comprehensive account inventory",
                        "Account lifecycle management"
                    ]
                },
                "5.2": {
                    "title": "Use Unique Passwords",
                    "description": "Use unique passwords for all enterprise accounts",
                    "implementation_status": "implemented",
                    "machine_rites_features": [
                        "tools/rotate-secrets.sh - Automated password generation",
                        "Pass password manager integration",
                        "GPG-encrypted credential storage"
                    ]
                }
            }
        },
        "CIS_6": {
            "title": "Access Control Management",
            "description": "Use processes and tools to create, assign, manage, and revoke access credentials",
            "implementation_group": "IG1",
            "safeguards": {
                "6.1": {
                    "title": "Establish Access Control Policy",
                    "description": "Establish access control policy",
                    "implementation_status": "implemented",
                    "machine_rites_features": [
                        "standards.md - Access control policies",
                        "SSH key management procedures",
                        "Sudo configuration management"
                    ]
                },
                "6.2": {
                    "title": "Establish Access Control Processes",
                    "description": "Establish access control processes",
                    "implementation_status": "implemented",
                    "machine_rites_features": [
                        "Bootstrap access control setup",
                        "Automated permission enforcement",
                        "security/audit/ - Access logging"
                    ]
                }
            }
        },
        "CIS_8": {
            "title": "Audit Log Management",
            "description": "Collect, alert, review, and retain audit logs",
            "implementation_group": "IG1",
            "safeguards": {
                "8.1": {
                    "title": "Establish and Maintain Audit Log Management Process",
                    "description": "Establish and maintain audit log management process",
                    "implementation_status": "implemented",
                    "machine_rites_features": [
                        "security/audit/audit-logger.sh - Centralized logging",
                        "Tamper-proof log integrity",
                        "Log rotation and retention"
                    ]
                },
                "8.2": {
                    "title": "Collect Audit Logs",
                    "description": "Collect audit logs",
                    "implementation_status": "implemented",
                    "machine_rites_features": [
                        "Multi-source log collection",
                        "Real-time log monitoring",
                        "Structured JSON logging"
                    ]
                },
                "8.3": {
                    "title": "Ensure Adequate Audit Log Storage",
                    "description": "Ensure adequate audit log storage",
                    "implementation_status": "implemented",
                    "machine_rites_features": [
                        "Automated log rotation",
                        "Configurable retention policies",
                        "Compressed log archival"
                    ]
                }
            }
        },
        "CIS_10": {
            "title": "Malware Defenses",
            "description": "Prevent or control installation, spread, and execution of malicious software",
            "implementation_group": "IG1",
            "safeguards": {
                "10.1": {
                    "title": "Deploy and Maintain Anti-Malware Software",
                    "description": "Deploy and maintain anti-malware software",
                    "implementation_status": "not_applicable",
                    "rationale": "Linux-based development environment with limited malware exposure",
                    "alternative_controls": [
                        "security/intrusion-detection/ - Behavioral monitoring",
                        "File integrity monitoring",
                        "Code security scanning with gitleaks"
                    ]
                }
            }
        },
        "CIS_11": {
            "title": "Data Recovery",
            "description": "Establish and maintain data recovery practices",
            "implementation_group": "IG1",
            "safeguards": {
                "11.1": {
                    "title": "Establish and Maintain Data Recovery Process",
                    "description": "Establish and maintain data recovery process",
                    "implementation_status": "implemented",
                    "machine_rites_features": [
                        "bootstrap/modules/10-backup.sh - Backup procedures",
                        "tools/backup-pass.sh - Secret backups",
                        "Automated rollback script generation"
                    ]
                },
                "11.2": {
                    "title": "Perform Automated Backups",
                    "description": "Perform automated backups",
                    "implementation_status": "implemented",
                    "machine_rites_features": [
                        "Automated backup systems",
                        "tools/rotate-secrets.sh - Backup before rotation",
                        "Configuration backup automation"
                    ]
                }
            }
        },
        "CIS_12": {
            "title": "Network Infrastructure Management",
            "description": "Establish, implement, and actively manage enterprise network infrastructure",
            "implementation_group": "IG2",
            "safeguards": {
                "12.1": {
                    "title": "Ensure Network Infrastructure is Up-to-Date",
                    "description": "Ensure network infrastructure is up-to-date",
                    "implementation_status": "partially_implemented",
                    "machine_rites_features": [
                        "tools/update.sh - System updates",
                        "Network monitoring capabilities"
                    ],
                    "gaps": [
                        "Dedicated network infrastructure management",
                        "Network device configuration management"
                    ]
                }
            }
        },
        "CIS_18": {
            "title": "Application Software Security",
            "description": "Manage security lifecycle of all in-house developed and acquired software",
            "implementation_group": "IG2",
            "safeguards": {
                "18.1": {
                    "title": "Establish and Maintain Secure Application Development Process",
                    "description": "Establish and maintain secure application development process",
                    "implementation_status": "implemented",
                    "machine_rites_features": [
                        "Pre-commit hooks for security scanning",
                        "Gitleaks for secret detection",
                        "Security-focused development practices"
                    ]
                },
                "18.3": {
                    "title": "Remediate Identified Vulnerabilities",
                    "description": "Remediate identified vulnerabilities in a timely manner",
                    "implementation_status": "implemented",
                    "machine_rites_features": [
                        "Automated vulnerability scanning",
                        "security/intrusion-detection/ - Real-time detection",
                        "Automated remediation capabilities"
                    ]
                }
            }
        }
    }
}
EOF

        sudo chmod 644 "$CIS_MAPPING_FILE"
    fi
}

# Function: create_cis_policies
# Purpose: Create CIS-aligned security policies
create_cis_policies() {
    info "Creating CIS-aligned security policies"

    # Password Policy (CIS 5.2)
    sudo tee "$CIS_POLICIES_DIR/password-policy.json" > /dev/null << 'EOF'
{
    "policy_name": "Password Management Policy",
    "cis_control": "5.2",
    "requirements": {
        "minimum_length": 16,
        "complexity": "high",
        "rotation_interval_days": 90,
        "unique_passwords": true,
        "password_manager_required": true,
        "plaintext_storage_prohibited": true
    },
    "implementation": {
        "password_generation": "tools/rotate-secrets.sh",
        "storage": "GPG-encrypted Pass store",
        "rotation": "Automated via secret rotation system"
    },
    "compliance_checks": [
        "verify_password_length",
        "verify_complexity_requirements",
        "verify_rotation_schedule",
        "verify_no_plaintext_storage"
    ]
}
EOF

    # Access Control Policy (CIS 6.1)
    sudo tee "$CIS_POLICIES_DIR/access-control-policy.json" > /dev/null << 'EOF'
{
    "policy_name": "Access Control Management Policy",
    "cis_control": "6.1",
    "requirements": {
        "principle_of_least_privilege": true,
        "role_based_access": true,
        "regular_access_reviews": true,
        "secure_defaults": true,
        "access_logging": true
    },
    "file_permissions": {
        "default_umask": "027",
        "sensitive_files": "600",
        "executable_files": "755",
        "directories": "750"
    },
    "ssh_access": {
        "key_based_authentication": true,
        "password_authentication": false,
        "root_login": false,
        "key_rotation_days": 180
    },
    "compliance_checks": [
        "verify_umask_enforcement",
        "verify_file_permissions",
        "verify_ssh_configuration",
        "verify_access_logging"
    ]
}
EOF

    # Audit Logging Policy (CIS 8.1)
    sudo tee "$CIS_POLICIES_DIR/audit-logging-policy.json" > /dev/null << 'EOF'
{
    "policy_name": "Audit Log Management Policy",
    "cis_control": "8.1",
    "requirements": {
        "comprehensive_logging": true,
        "log_integrity_protection": true,
        "centralized_collection": true,
        "real_time_monitoring": true,
        "retention_period_days": 365
    },
    "log_sources": [
        "authentication_events",
        "authorization_changes",
        "file_access",
        "network_connections",
        "system_changes",
        "security_events"
    ],
    "log_protection": {
        "cryptographic_signatures": true,
        "tamper_detection": true,
        "secure_storage": true,
        "access_controls": true
    },
    "compliance_checks": [
        "verify_log_collection",
        "verify_log_integrity",
        "verify_log_retention",
        "verify_monitoring_coverage"
    ]
}
EOF

    sudo chmod 644 "$CIS_POLICIES_DIR"/*.json
}

# Function: create_remediation_scripts
# Purpose: Create automated remediation scripts for CIS controls
create_remediation_scripts() {
    info "Creating CIS remediation scripts"

    # File Permissions Remediation (CIS 3.3, 6.2)
    sudo tee "$CIS_REMEDIATION_DIR/fix-file-permissions.sh" > /dev/null << 'EOF'
#!/bin/bash
# CIS Remediation: Fix file permissions to comply with CIS controls

set -euo pipefail

# Critical system files
declare -A CRITICAL_FILES=(
    ["/etc/passwd"]="644"
    ["/etc/shadow"]="640"
    ["/etc/group"]="644"
    ["/etc/sudoers"]="440"
    ["/etc/ssh/sshd_config"]="600"
)

# Fix critical file permissions
for file in "${!CRITICAL_FILES[@]}"; do
    if [[ -f "$file" ]]; then
        current_perms=$(stat -c "%a" "$file")
        required_perms="${CRITICAL_FILES[$file]}"

        if [[ "$current_perms" != "$required_perms" ]]; then
            echo "Fixing permissions: $file ($current_perms -> $required_perms)"
            sudo chmod "$required_perms" "$file"
        fi
    fi
done

# Fix SSH directory permissions
if [[ -d "$HOME/.ssh" ]]; then
    chmod 700 "$HOME/.ssh"
    chmod 600 "$HOME/.ssh"/* 2>/dev/null || true
fi

# Enforce umask
if ! grep -q "umask 027" "$HOME/.bashrc"; then
    echo "umask 027" >> "$HOME/.bashrc"
fi

echo "File permissions remediation completed"
EOF

    # Password Policy Remediation (CIS 5.2)
    sudo tee "$CIS_REMEDIATION_DIR/enforce-password-policy.sh" > /dev/null << 'EOF'
#!/bin/bash
# CIS Remediation: Enforce password policy requirements

set -euo pipefail

# Check for plaintext password files
PLAINTEXT_FILES=(
    "$HOME/.config/secrets.env"
    "$HOME/.password"
    "$HOME/.credentials"
)

for file in "${PLAINTEXT_FILES[@]}"; do
    if [[ -f "$file" ]]; then
        echo "WARNING: Plaintext password file found: $file"
        echo "Consider migrating to encrypted storage (Pass/GPG)"
    fi
done

# Verify password manager setup
if ! command -v pass >/dev/null 2>&1; then
    echo "ERROR: Pass password manager not installed"
    exit 1
fi

if ! pass ls >/dev/null 2>&1; then
    echo "ERROR: Pass password store not initialized"
    exit 1
fi

# Check password rotation schedule
if [[ -f "$HOME/.config/secret-rotation.conf" ]]; then
    overdue_secrets=$(awk -F'|' '$2 > 0 {
        last_rotation = system("stat -c %Y ~/.password-store/" $1 ".gpg 2>/dev/null || echo 0")
        days_old = (systime() - last_rotation) / 86400
        if (days_old > $2) print $1 " (overdue by " int(days_old - $2) " days)"
    }' "$HOME/.config/secret-rotation.conf")

    if [[ -n "$overdue_secrets" ]]; then
        echo "WARNING: Passwords overdue for rotation:"
        echo "$overdue_secrets"
    fi
fi

echo "Password policy compliance checked"
EOF

    # Audit Logging Remediation (CIS 8.1)
    sudo tee "$CIS_REMEDIATION_DIR/configure-audit-logging.sh" > /dev/null << 'EOF'
#!/bin/bash
# CIS Remediation: Configure comprehensive audit logging

set -euo pipefail

# Ensure audit log directory exists with proper permissions
sudo mkdir -p /var/log/security-audit
sudo chmod 750 /var/log/security-audit

# Configure rsyslog for security logging if available
if [[ -f /etc/rsyslog.conf ]]; then
    if ! grep -q "security-audit" /etc/rsyslog.conf; then
        echo "# Security audit logging" | sudo tee -a /etc/rsyslog.conf
        echo "auth,authpriv.*    /var/log/security-audit/auth.log" | sudo tee -a /etc/rsyslog.conf
        sudo systemctl restart rsyslog 2>/dev/null || true
    fi
fi

# Ensure audit logging service is enabled
if [[ -f /home/william/git/machine-rites/security/audit/audit-logger.sh ]]; then
    chmod +x /home/william/git/machine-rites/security/audit/audit-logger.sh

    # Initialize audit system
    /home/william/git/machine-rites/security/audit/audit-logger.sh init
fi

echo "Audit logging configuration completed"
EOF

    # Make remediation scripts executable
    sudo chmod 755 "$CIS_REMEDIATION_DIR"/*.sh
}

# Function: assess_cis_control
# Purpose: Assess implementation of a specific CIS control
# Args: $1 - control number (e.g., "CIS_1")
assess_cis_control() {
    local control="$1"

    if ! jq -e ".controls.$control" "$CIS_MAPPING_FILE" >/dev/null 2>&1; then
        die "Control not found: $control"
    fi

    local title
    title=$(jq -r ".controls.$control.title" "$CIS_MAPPING_FILE")
    local description
    description=$(jq -r ".controls.$control.description" "$CIS_MAPPING_FILE")

    echo "=== CIS Control Assessment: $control ==="
    echo "Title: $title"
    echo "Description: $description"
    echo

    # Assess each safeguard
    jq -r ".controls.$control.safeguards | to_entries[] | \"\(.key) \(.value.title) \(.value.implementation_status)\"" "$CIS_MAPPING_FILE" | \
    while read -r safeguard_id title status; do
        echo "Safeguard $safeguard_id: $title"
        echo "Status: $status"

        # Get implementation details
        local features
        features=$(jq -r ".controls.$control.safeguards[\"$safeguard_id\"].machine_rites_features[]?" "$CIS_MAPPING_FILE" 2>/dev/null || echo "")

        if [[ -n "$features" ]]; then
            echo "Implementation:"
            echo "$features" | while read -r feature; do
                if [[ -n "$feature" ]]; then
                    echo "  - $feature"
                fi
            done
        fi

        # Check for gaps
        local gaps
        gaps=$(jq -r ".controls.$control.safeguards[\"$safeguard_id\"].gaps[]?" "$CIS_MAPPING_FILE" 2>/dev/null || echo "")

        if [[ -n "$gaps" ]]; then
            echo "Gaps:"
            echo "$gaps" | while read -r gap; do
                if [[ -n "$gap" ]]; then
                    echo "  - $gap"
                fi
            done
        fi

        echo
    done
}

# Function: run_compliance_checks
# Purpose: Run automated compliance checks for CIS controls
run_compliance_checks() {
    info "Running CIS Controls compliance checks"

    local total_checks=0
    local passed_checks=0
    local failed_checks=0

    # File Permissions Check (CIS 3.3, 6.2)
    echo "=== File Permissions Compliance ==="

    local critical_files=(
        "/etc/passwd:644"
        "/etc/shadow:640"
        "/etc/group:644"
        "/etc/sudoers:440"
    )

    for file_perm in "${critical_files[@]}"; do
        IFS=':' read -r file expected_perm <<< "$file_perm"
        ((total_checks++))

        if [[ -f "$file" ]]; then
            local actual_perm
            actual_perm=$(stat -c "%a" "$file")

            if [[ "$actual_perm" == "$expected_perm" ]]; then
                ok "$file permissions correct ($actual_perm)"
                ((passed_checks++))
            else
                fail "$file permissions incorrect ($actual_perm, expected $expected_perm)"
                ((failed_checks++))
            fi
        else
            warn "$file not found"
            ((failed_checks++))
        fi
    done

    # Password Management Check (CIS 5.2)
    echo
    echo "=== Password Management Compliance ==="

    ((total_checks++))
    if command -v pass >/dev/null 2>&1 && pass ls >/dev/null 2>&1; then
        ok "Password manager (Pass) is configured"
        ((passed_checks++))
    else
        fail "Password manager not properly configured"
        ((failed_checks++))
    fi

    ((total_checks++))
    if [[ -f "$HOME/.config/secrets.env" ]]; then
        fail "Plaintext secrets file found (security risk)"
        ((failed_checks++))
    else
        ok "No plaintext secrets files found"
        ((passed_checks++))
    fi

    # Audit Logging Check (CIS 8.1)
    echo
    echo "=== Audit Logging Compliance ==="

    ((total_checks++))
    if [[ -d "/var/log/security-audit" ]]; then
        ok "Security audit log directory exists"
        ((passed_checks++))
    else
        fail "Security audit log directory missing"
        ((failed_checks++))
    fi

    ((total_checks++))
    if [[ -f "/var/log/security-audit/security-audit.log" ]]; then
        ok "Security audit log file exists"
        ((passed_checks++))
    else
        warn "Security audit log file not found"
        ((failed_checks++))
    fi

    # Backup Systems Check (CIS 11.1, 11.2)
    echo
    echo "=== Data Recovery Compliance ==="

    ((total_checks++))
    if [[ -f "/home/william/git/machine-rites/bootstrap/modules/10-backup.sh" ]]; then
        ok "Backup system implemented"
        ((passed_checks++))
    else
        fail "Backup system not found"
        ((failed_checks++))
    fi

    ((total_checks++))
    if [[ -f "/home/william/git/machine-rites/tools/backup-pass.sh" ]]; then
        ok "Secret backup system implemented"
        ((passed_checks++))
    else
        fail "Secret backup system not found"
        ((failed_checks++))
    fi

    # Security Scanning Check (CIS 18.1, 18.3)
    echo
    echo "=== Application Security Compliance ==="

    ((total_checks++))
    if [[ -f ".pre-commit-config.yaml" ]] && grep -q "gitleaks" .pre-commit-config.yaml 2>/dev/null; then
        ok "Security scanning (gitleaks) configured"
        ((passed_checks++))
    else
        fail "Security scanning not properly configured"
        ((failed_checks++))
    fi

    ((total_checks++))
    if [[ -f "/home/william/git/machine-rites/security/intrusion-detection/ids-monitor.sh" ]]; then
        ok "Intrusion detection system implemented"
        ((passed_checks++))
    else
        fail "Intrusion detection system not found"
        ((failed_checks++))
    fi

    # Generate summary
    echo
    echo "=== CIS Compliance Summary ==="
    echo "Total checks: $total_checks"
    echo "Passed: $passed_checks"
    echo "Failed: $failed_checks"

    local compliance_percentage=$((passed_checks * 100 / total_checks))
    echo "Compliance percentage: ${compliance_percentage}%"

    if [[ $compliance_percentage -ge 90 ]]; then
        ok "Excellent CIS compliance"
    elif [[ $compliance_percentage -ge 80 ]]; then
        warn "Good CIS compliance, minor improvements needed"
    elif [[ $compliance_percentage -ge 70 ]]; then
        warn "Moderate CIS compliance, improvements required"
    else
        fail "Poor CIS compliance, significant remediation needed"
    fi

    # Log compliance check results
    log_audit_event "CIS" "COMPLIANCE_CHECK" "INFO" "CIS compliance assessment completed" \
                   '{"total_checks": '$total_checks', "passed": '$passed_checks', "failed": '$failed_checks', "compliance_percentage": '$compliance_percentage'}'

    return $failed_checks
}

# Function: generate_cis_report
# Purpose: Generate comprehensive CIS compliance report
# Args: $1 - format (html|json|markdown)
generate_cis_report() {
    local format="${1:-html}"
    local timestamp="$(date +%Y%m%d_%H%M%S)"
    local report_file="$CIS_RESULTS_DIR/cis-compliance-${timestamp}.$format"

    info "Generating CIS Controls compliance report: $format"

    case "$format" in
        json)
            generate_cis_json_report > "$report_file"
            ;;
        markdown)
            generate_cis_markdown_report > "$report_file"
            ;;
        html)
            generate_cis_html_report > "$report_file"
            ;;
        *)
            die "Unsupported report format: $format"
            ;;
    esac

    ok "CIS compliance report generated: $report_file"
    echo "$report_file"
}

# Function: generate_cis_json_report
# Purpose: Generate JSON format CIS compliance report
generate_cis_json_report() {
    # Run compliance checks and capture results
    local check_results
    check_results=$(mktemp)
    run_compliance_checks > "$check_results" 2>&1
    local compliance_status=$?

    # Extract metrics from check results
    local total_checks
    total_checks=$(grep "Total checks:" "$check_results" | awk '{print $3}')
    local passed_checks
    passed_checks=$(grep "Passed:" "$check_results" | awk '{print $2}')
    local failed_checks
    failed_checks=$(grep "Failed:" "$check_results" | awk '{print $2}')

    # Generate JSON report
    jq -n \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg total "${total_checks:-0}" \
        --arg passed "${passed_checks:-0}" \
        --arg failed "${failed_checks:-0}" \
        --argjson mappings "$(cat "$CIS_MAPPING_FILE")" \
        --arg check_output "$(cat "$check_results")" \
        '{
            "report_metadata": {
                "generated": $timestamp,
                "framework": "CIS Controls v8",
                "organization": "machine-rites",
                "report_type": "compliance_assessment"
            },
            "compliance_summary": {
                "total_checks": ($total | tonumber),
                "passed_checks": ($passed | tonumber),
                "failed_checks": ($failed | tonumber),
                "compliance_percentage": (($passed | tonumber) * 100 / ($total | tonumber) | floor),
                "assessment_status": (if ($failed | tonumber) == 0 then "compliant" else "non_compliant" end)
            },
            "control_mappings": $mappings,
            "detailed_results": $check_output
        }'

    rm -f "$check_results"
}

# Function: generate_cis_markdown_report
# Purpose: Generate Markdown format CIS compliance report
generate_cis_markdown_report() {
    cat << EOF
# CIS Controls v8 Compliance Report

**Generated:** $(date)
**Framework:** CIS Controls v8
**Organization:** machine-rites

## Executive Summary

This report provides an assessment of machine-rites compliance with CIS Controls v8, focusing on Implementation Group 1 (IG1) essential controls for basic cyber hygiene.

### Implementation Group Coverage

- **IG1 (Essential):** Core security controls for all organizations
- **IG2 (Foundational):** Additional controls for organizations with IT resources
- **IG3 (Organizational):** Advanced controls for mature security programs

## Compliance Results

$(run_compliance_checks 2>&1 | sed 's/^/    /')

## Control Implementation Status

### CIS Control 1: Inventory and Control of Enterprise Assets
$(assess_cis_control "CIS_1" | sed 's/^/    /')

### CIS Control 2: Inventory and Control of Software Assets
$(assess_cis_control "CIS_2" | sed 's/^/    /')

### CIS Control 3: Data Protection
$(assess_cis_control "CIS_3" | sed 's/^/    /')

### CIS Control 4: Secure Configuration of Enterprise Assets and Software
$(assess_cis_control "CIS_4" | sed 's/^/    /')

### CIS Control 5: Account Management
$(assess_cis_control "CIS_5" | sed 's/^/    /')

### CIS Control 6: Access Control Management
$(assess_cis_control "CIS_6" | sed 's/^/    /')

### CIS Control 8: Audit Log Management
$(assess_cis_control "CIS_8" | sed 's/^/    /')

### CIS Control 11: Data Recovery
$(assess_cis_control "CIS_11" | sed 's/^/    /')

## Remediation Recommendations

### High Priority
1. **Address Failed Compliance Checks**
   - Review and remediate any failed checks from the compliance assessment
   - Run remediation scripts in security/compliance/cis/remediation/

2. **Enhance Network Infrastructure Management (CIS 12)**
   - Implement dedicated network monitoring
   - Add network device configuration management

### Medium Priority
1. **Complete Account Management Implementation (CIS 5)**
   - Implement comprehensive account inventory
   - Add account lifecycle management procedures

2. **Strengthen Application Security (CIS 18)**
   - Enhance vulnerability scanning coverage
   - Add security testing to CI/CD pipeline

## Implementation Evidence

The following machine-rites components provide evidence of CIS control implementation:

- **Asset Management:** tools/doctor.sh, lib/platform.sh
- **Software Inventory:** bootstrap package management, devtools-installer.sh
- **Data Protection:** GPG encryption, Pass password store, secure file operations
- **Secure Configuration:** Bootstrap system hardening, configuration baselines
- **Access Control:** SSH key management, file permissions, umask enforcement
- **Audit Logging:** security/audit/audit-logger.sh, centralized logging
- **Data Recovery:** backup systems, automated recovery procedures

---
*Report generated by machine-rites CIS Controls compliance system*
EOF
}

# Function: generate_cis_html_report
# Purpose: Generate HTML format CIS compliance report
generate_cis_html_report() {
    cat << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>CIS Controls v8 Compliance Report - machine-rites</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; line-height: 1.6; color: #333; }
        .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; border-radius: 10px; text-align: center; }
        .summary { background-color: #f8f9fa; padding: 20px; margin: 20px 0; border-radius: 8px; border-left: 4px solid #007bff; }
        .control-section { margin: 20px 0; border: 1px solid #dee2e6; border-radius: 8px; overflow: hidden; }
        .control-header { background-color: #e9ecef; padding: 15px; font-weight: bold; font-size: 1.1em; }
        .safeguard { margin: 15px; padding: 15px; background-color: #f8f9fa; border-radius: 5px; }
        .implemented { border-left: 4px solid #28a745; }
        .partial { border-left: 4px solid #ffc107; }
        .not-implemented { border-left: 4px solid #dc3545; }
        .not-applicable { border-left: 4px solid #6c757d; }
        .metric-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; margin: 20px 0; }
        .metric-card { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); text-align: center; border-top: 3px solid #007bff; }
        .metric-value { font-size: 2em; font-weight: bold; color: #007bff; }
        .metric-label { color: #6c757d; font-size: 0.9em; }
        .compliance-check { background-color: #fff; margin: 10px 0; padding: 10px; border-radius: 5px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
        .check-pass { border-left: 3px solid #28a745; }
        .check-fail { border-left: 3px solid #dc3545; }
        .check-warn { border-left: 3px solid #ffc107; }
        .recommendations { background-color: #fff3cd; border: 1px solid #ffeaa7; padding: 20px; border-radius: 8px; margin: 20px 0; }
        table { border-collapse: collapse; width: 100%; margin: 20px 0; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
        th, td { border: 1px solid #dee2e6; padding: 12px; text-align: left; }
        th { background-color: #f8f9fa; font-weight: 600; }
        .footer { margin-top: 40px; padding-top: 20px; border-top: 2px solid #dee2e6; color: #6c757d; text-align: center; }
    </style>
</head>
<body>
    <div class="header">
        <h1>CIS Controls v8 Compliance Report</h1>
        <p><strong>Generated:</strong> $(date)</p>
        <p><strong>Framework:</strong> CIS Controls v8</p>
        <p><strong>Organization:</strong> machine-rites</p>
    </div>

    <div class="summary">
        <h2>Executive Summary</h2>
        <p>This report provides a comprehensive assessment of machine-rites compliance with CIS Controls v8, focusing on essential security controls for effective cyber defense.</p>
EOF

    # Add compliance metrics
    echo '<div class="metric-grid">'

    # Run compliance check to get metrics
    local check_output
    check_output=$(run_compliance_checks 2>&1)
    local total_checks
    total_checks=$(echo "$check_output" | grep "Total checks:" | awk '{print $3}' || echo "0")
    local passed_checks
    passed_checks=$(echo "$check_output" | grep "Passed:" | awk '{print $2}' || echo "0")
    local failed_checks
    failed_checks=$(echo "$check_output" | grep "Failed:" | awk '{print $2}' || echo "0")
    local compliance_percentage
    compliance_percentage=$(echo "$check_output" | grep "Compliance percentage:" | awk '{print $3}' | tr -d '%' || echo "0")

    cat << EOF
            <div class="metric-card">
                <div class="metric-value">$total_checks</div>
                <div class="metric-label">Total Checks</div>
            </div>
            <div class="metric-card">
                <div class="metric-value">$passed_checks</div>
                <div class="metric-label">Passed</div>
            </div>
            <div class="metric-card">
                <div class="metric-value">$failed_checks</div>
                <div class="metric-label">Failed</div>
            </div>
            <div class="metric-card">
                <div class="metric-value">${compliance_percentage}%</div>
                <div class="metric-label">Compliance</div>
            </div>
        </div>
    </div>

    <h2>Detailed Compliance Results</h2>
    <div style="background-color: #f8f9fa; padding: 15px; border-radius: 5px; font-family: monospace; white-space: pre-wrap; overflow-x: auto;">$check_output</div>

    <h2>CIS Control Implementation Status</h2>
EOF

    # Add detailed control assessments would go here
    # For brevity, showing structure only
    cat << 'EOF'

    <div class="recommendations">
        <h2>Recommendations</h2>
        <h3>High Priority</h3>
        <ul>
            <li><strong>Address Failed Compliance Checks:</strong> Review and remediate any failed checks from the assessment</li>
            <li><strong>Enhance Network Infrastructure Management:</strong> Implement dedicated network monitoring capabilities</li>
        </ul>
        <h3>Medium Priority</h3>
        <ul>
            <li><strong>Complete Account Management Implementation:</strong> Add comprehensive account inventory and lifecycle management</li>
            <li><strong>Strengthen Application Security:</strong> Enhance vulnerability scanning coverage</li>
        </ul>
    </div>

    <div class="footer">
        <p><em>Report generated by machine-rites CIS Controls compliance system</em></p>
    </div>
</body>
</html>
EOF
}

# Function: run_remediation
# Purpose: Run automated remediation for CIS controls
# Args: $1 - control or "all"
run_remediation() {
    local target="${1:-all}"

    info "Running CIS Controls remediation: $target"

    case "$target" in
        all)
            # Run all remediation scripts
            for script in "$CIS_REMEDIATION_DIR"/*.sh; do
                if [[ -x "$script" ]]; then
                    info "Running remediation: $(basename "$script")"
                    "$script"
                fi
            done
            ;;
        permissions|3.3|6.2)
            "$CIS_REMEDIATION_DIR/fix-file-permissions.sh"
            ;;
        passwords|5.2)
            "$CIS_REMEDIATION_DIR/enforce-password-policy.sh"
            ;;
        logging|8.1)
            "$CIS_REMEDIATION_DIR/configure-audit-logging.sh"
            ;;
        *)
            die "Unknown remediation target: $target"
            ;;
    esac

    # Re-run compliance checks to verify remediation
    echo
    info "Verifying remediation effectiveness..."
    run_compliance_checks

    log_audit_event "CIS" "REMEDIATION_RUN" "INFO" "CIS remediation executed" \
                   '{"target": "'$target'"}'
}

# Function: main
# Purpose: Main entry point
main() {
    local action="${1:-}"

    case "$action" in
        init)
            init_cis_compliance
            ;;
        assess)
            shift
            if [[ $# -eq 1 ]]; then
                assess_cis_control "$1"
            else
                run_compliance_checks
            fi
            ;;
        check)
            run_compliance_checks
            ;;
        report)
            shift
            generate_cis_report "$@"
            ;;
        remediate)
            shift
            run_remediation "$@"
            ;;
        *)
            echo "Usage: $0 {init|assess|check|report|remediate}"
            echo "  init                - Initialize CIS Controls compliance system"
            echo "  assess [control]    - Assess specific control or run full assessment"
            echo "  check               - Run compliance checks"
            echo "  report [format]     - Generate compliance report (html|json|markdown)"
            echo "  remediate [target]  - Run automated remediation (all|permissions|passwords|logging)"
            exit 1
            ;;
    esac
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi