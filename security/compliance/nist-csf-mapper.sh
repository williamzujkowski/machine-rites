#!/usr/bin/env bash
# security/compliance/nist-csf-mapper.sh - NIST Cybersecurity Framework Mapper
#
# Description: Map machine-rites features to NIST CSF controls and generate compliance reports
# Version: 1.0.0
# Dependencies: lib/validation.sh, lib/common.sh, jq
# Security: Compliance reporting, control mapping, evidence collection
#
# Features:
#   - NIST CSF 2.0 control mapping
#   - Automated evidence collection
#   - Compliance gap analysis
#   - Remediation recommendations
#   - Executive reporting

set -euo pipefail

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"
# shellcheck source=../../lib/validation.sh
source "$SCRIPT_DIR/../../lib/validation.sh"

# Configuration
readonly COMPLIANCE_DIR="/etc/security/compliance"
readonly NIST_MAPPING_FILE="$COMPLIANCE_DIR/nist-csf-mapping.json"
readonly EVIDENCE_DIR="$COMPLIANCE_DIR/evidence"
readonly REPORTS_DIR="$COMPLIANCE_DIR/reports"
readonly CONTROLS_DB="$COMPLIANCE_DIR/controls.json"

# Secure permissions
umask 027

# Function: init_nist_compliance
# Purpose: Initialize NIST CSF compliance system
init_nist_compliance() {
    info "Initializing NIST Cybersecurity Framework compliance system"

    # Create directories
    sudo mkdir -p "$COMPLIANCE_DIR" "$EVIDENCE_DIR" "$REPORTS_DIR"
    sudo chmod 750 "$COMPLIANCE_DIR" "$EVIDENCE_DIR" "$REPORTS_DIR"

    # Create NIST CSF control mappings
    create_nist_mappings

    # Create controls database
    create_controls_database

    # Initialize evidence collection
    setup_evidence_collection

    ok "NIST CSF compliance system initialized"
}

# Function: create_nist_mappings
# Purpose: Create comprehensive NIST CSF control mappings
create_nist_mappings() {
    if [[ ! -f "$NIST_MAPPING_FILE" ]]; then
        info "Creating NIST CSF control mappings"

        sudo tee "$NIST_MAPPING_FILE" > /dev/null << 'EOF'
{
    "framework": "NIST Cybersecurity Framework 2.0",
    "version": "2.0",
    "organization": "machine-rites",
    "last_updated": "2024-01-01T00:00:00Z",
    "functions": {
        "identify": {
            "ID.AM": {
                "name": "Asset Management",
                "description": "Develop organizational understanding to manage cybersecurity risk",
                "controls": {
                    "ID.AM-1": {
                        "description": "Physical devices and systems within the organization are inventoried",
                        "implementation_status": "implemented",
                        "evidence": [
                            "tools/doctor.sh system inventory",
                            "bootstrap system detection",
                            "platform detection in lib/platform.sh"
                        ],
                        "machine_rites_features": [
                            "bootstrap/modules/00-prereqs.sh - System detection",
                            "lib/platform.sh - Hardware/OS inventory",
                            "tools/doctor.sh - System health checks"
                        ]
                    },
                    "ID.AM-2": {
                        "description": "Software platforms and applications within the organization are inventoried",
                        "implementation_status": "implemented",
                        "evidence": [
                            "devtools-installer.sh package inventory",
                            "bootstrap package management",
                            "tools/update.sh version tracking"
                        ],
                        "machine_rites_features": [
                            "bootstrap/modules/20-system-packages.sh - Package inventory",
                            "devtools-installer.sh - Development tools catalog",
                            "tools/update.sh - Version management"
                        ]
                    }
                }
            },
            "ID.GV": {
                "name": "Governance",
                "description": "Policies, procedures, and processes to manage and monitor cybersecurity risk",
                "controls": {
                    "ID.GV-1": {
                        "description": "Organizational cybersecurity policy is established and communicated",
                        "implementation_status": "implemented",
                        "evidence": [
                            "standards.md security policies",
                            "Security documentation",
                            "project-plan.md security requirements"
                        ],
                        "machine_rites_features": [
                            "standards.md - Security standards",
                            "CLAUDE.md - Security guidelines",
                            "security/ - Security framework"
                        ]
                    }
                }
            },
            "ID.RA": {
                "name": "Risk Assessment",
                "description": "Understanding cybersecurity risk to organizational operations",
                "controls": {
                    "ID.RA-1": {
                        "description": "Asset vulnerabilities are identified and documented",
                        "implementation_status": "implemented",
                        "evidence": [
                            "security vulnerability scanning",
                            "Code security analysis",
                            "Dependency vulnerability checks"
                        ],
                        "machine_rites_features": [
                            "bootstrap/modules/60-devtools.sh - Gitleaks setup",
                            "security/intrusion-detection/ - Vulnerability detection",
                            ".pre-commit-config.yaml - Security scanning"
                        ]
                    }
                }
            }
        },
        "protect": {
            "PR.AC": {
                "name": "Access Control",
                "description": "Access to physical and logical assets is limited to authorized personnel",
                "controls": {
                    "PR.AC-1": {
                        "description": "Identities and credentials are issued, managed, verified, revoked for authorized devices and users",
                        "implementation_status": "implemented",
                        "evidence": [
                            "GPG key management",
                            "SSH key management",
                            "Pass password store",
                            "Secret rotation system"
                        ],
                        "machine_rites_features": [
                            "bootstrap/modules/50-secrets.sh - GPG/Pass setup",
                            "tools/rotate-secrets.sh - Credential rotation",
                            "bootstrap SSH key management",
                            "security/audit/ - Access logging"
                        ]
                    },
                    "PR.AC-3": {
                        "description": "Remote access is managed",
                        "implementation_status": "implemented",
                        "evidence": [
                            "SSH configuration management",
                            "Remote access logging",
                            "VPN configuration"
                        ],
                        "machine_rites_features": [
                            "bootstrap SSH agent setup",
                            ".chezmoi/dot_bashrc.d/35-ssh.sh - SSH config",
                            "security/audit/ - Remote access logging"
                        ]
                    },
                    "PR.AC-4": {
                        "description": "Access permissions and authorizations are managed",
                        "implementation_status": "implemented",
                        "evidence": [
                            "File permission management",
                            "Umask enforcement",
                            "Sudo configuration"
                        ],
                        "machine_rites_features": [
                            "lib/atomic.sh - Secure file operations",
                            "bootstrap umask 027 enforcement",
                            "security/intrusion-detection/ - Permission monitoring"
                        ]
                    }
                }
            },
            "PR.DS": {
                "name": "Data Security",
                "description": "Information and records are managed consistent with risk strategy",
                "controls": {
                    "PR.DS-1": {
                        "description": "Data-at-rest is protected",
                        "implementation_status": "implemented",
                        "evidence": [
                            "GPG encryption for secrets",
                            "Encrypted password store",
                            "Secure file permissions"
                        ],
                        "machine_rites_features": [
                            "bootstrap/modules/50-secrets.sh - GPG encryption",
                            "tools/backup-pass.sh - Encrypted backups",
                            "lib/atomic.sh - Secure temporary files"
                        ]
                    },
                    "PR.DS-2": {
                        "description": "Data-in-transit is protected",
                        "implementation_status": "partially_implemented",
                        "evidence": [
                            "SSH for remote access",
                            "HTTPS for downloads",
                            "TLS enforcement"
                        ],
                        "machine_rites_features": [
                            "SSH key management",
                            "HTTPS URL validation in lib/validation.sh",
                            "Secure download procedures"
                        ]
                    },
                    "PR.DS-5": {
                        "description": "Protections against data leaks are implemented",
                        "implementation_status": "implemented",
                        "evidence": [
                            "Gitleaks secret scanning",
                            "Pre-commit hooks",
                            "Secret detection rules"
                        ],
                        "machine_rites_features": [
                            "bootstrap/modules/60-devtools.sh - Gitleaks setup",
                            ".pre-commit-config.yaml - Secret scanning",
                            ".gitleaks.toml - Detection rules"
                        ]
                    }
                }
            },
            "PR.IP": {
                "name": "Information Protection Processes",
                "description": "Security policies, processes, and procedures are maintained",
                "controls": {
                    "PR.IP-1": {
                        "description": "A baseline configuration of information technology/industrial control systems is created",
                        "implementation_status": "implemented",
                        "evidence": [
                            "Bootstrap system configuration",
                            "Standardized setup procedures",
                            "Configuration management"
                        ],
                        "machine_rites_features": [
                            "bootstrap/ - System baseline",
                            "bootstrap/modules/ - Standardized configs",
                            "tools/doctor.sh - Configuration validation"
                        ]
                    }
                }
            }
        },
        "detect": {
            "DE.AE": {
                "name": "Anomalies and Events",
                "description": "Anomalous activity is detected and impact of events is understood",
                "controls": {
                    "DE.AE-1": {
                        "description": "A baseline of network operations and expected data flows is established",
                        "implementation_status": "partially_implemented",
                        "evidence": [
                            "Network monitoring setup",
                            "Connection tracking",
                            "Baseline establishment"
                        ],
                        "machine_rites_features": [
                            "security/intrusion-detection/ - Network monitoring",
                            "security/audit/ - Connection logging"
                        ]
                    },
                    "DE.AE-3": {
                        "description": "Event data are collected and correlated from multiple sources",
                        "implementation_status": "implemented",
                        "evidence": [
                            "Centralized audit logging",
                            "Multi-source log collection",
                            "Event correlation"
                        ],
                        "machine_rites_features": [
                            "security/audit/audit-logger.sh - Centralized logging",
                            "security/intrusion-detection/ - Event correlation",
                            "Syslog integration"
                        ]
                    }
                }
            },
            "DE.CM": {
                "name": "Security Continuous Monitoring",
                "description": "The information system and assets are monitored to identify cybersecurity events",
                "controls": {
                    "DE.CM-1": {
                        "description": "The network is monitored to detect potential cybersecurity events",
                        "implementation_status": "implemented",
                        "evidence": [
                            "Real-time network monitoring",
                            "Intrusion detection system",
                            "Network anomaly detection"
                        ],
                        "machine_rites_features": [
                            "security/intrusion-detection/ids-monitor.sh - Network monitoring",
                            "Real-time log analysis",
                            "Anomaly detection rules"
                        ]
                    },
                    "DE.CM-7": {
                        "description": "Monitoring for unauthorized personnel, connections, devices, and software is performed",
                        "implementation_status": "implemented",
                        "evidence": [
                            "File integrity monitoring",
                            "Access monitoring",
                            "Change detection"
                        ],
                        "machine_rites_features": [
                            "security/intrusion-detection/ - FIM",
                            "security/audit/ - Access logging",
                            "Real-time file monitoring"
                        ]
                    }
                }
            }
        },
        "respond": {
            "RS.RP": {
                "name": "Response Planning",
                "description": "Response processes and procedures are executed and maintained",
                "controls": {
                    "RS.RP-1": {
                        "description": "Response plan is executed during or after an incident",
                        "implementation_status": "implemented",
                        "evidence": [
                            "Automated incident response",
                            "Response procedures",
                            "Escalation protocols"
                        ],
                        "machine_rites_features": [
                            "security/intrusion-detection/ - Automated response",
                            "security/audit/ - Incident logging",
                            "Alert mechanisms"
                        ]
                    }
                }
            },
            "RS.MI": {
                "name": "Mitigation",
                "description": "Activities are performed to prevent expansion of an event",
                "controls": {
                    "RS.MI-3": {
                        "description": "Newly identified vulnerabilities are mitigated or documented as accepted risks",
                        "implementation_status": "implemented",
                        "evidence": [
                            "Vulnerability tracking",
                            "Mitigation procedures",
                            "Risk acceptance documentation"
                        ],
                        "machine_rites_features": [
                            "security/intrusion-detection/ - Auto-mitigation",
                            "tools/rotate-secrets.sh - Credential rotation",
                            "Quarantine capabilities"
                        ]
                    }
                }
            }
        },
        "recover": {
            "RC.RP": {
                "name": "Recovery Planning",
                "description": "Recovery processes and procedures are executed and maintained",
                "controls": {
                    "RC.RP-1": {
                        "description": "A recovery plan is executed during or after a cybersecurity incident",
                        "implementation_status": "implemented",
                        "evidence": [
                            "Backup and restore procedures",
                            "Recovery automation",
                            "System rollback capabilities"
                        ],
                        "machine_rites_features": [
                            "bootstrap/modules/10-backup.sh - Backup system",
                            "tools/backup-pass.sh - Secret backups",
                            "Rollback scripts generation"
                        ]
                    }
                }
            }
        }
    }
}
EOF

        sudo chmod 644 "$NIST_MAPPING_FILE"
    fi
}

# Function: create_controls_database
# Purpose: Create comprehensive controls database
create_controls_database() {
    if [[ ! -f "$CONTROLS_DB" ]]; then
        info "Creating controls database"

        sudo tee "$CONTROLS_DB" > /dev/null << 'EOF'
{
    "controls_metadata": {
        "total_controls": 108,
        "implemented": 0,
        "partially_implemented": 0,
        "not_implemented": 0,
        "not_applicable": 0
    },
    "implementation_levels": {
        "implemented": {
            "description": "Control is fully implemented and operational",
            "color": "green",
            "score": 100
        },
        "partially_implemented": {
            "description": "Control is partially implemented, some gaps exist",
            "color": "yellow",
            "score": 50
        },
        "not_implemented": {
            "description": "Control is not implemented",
            "color": "red",
            "score": 0
        },
        "not_applicable": {
            "description": "Control is not applicable to this environment",
            "color": "gray",
            "score": "N/A"
        }
    },
    "assessment_criteria": {
        "evidence_requirements": [
            "Technical implementation",
            "Process documentation",
            "Training records",
            "Testing results",
            "Monitoring data"
        ],
        "scoring_methodology": "NIST CSF Implementation Tiers",
        "assessment_frequency": "Quarterly"
    }
}
EOF

        sudo chmod 644 "$CONTROLS_DB"
    fi
}

# Function: setup_evidence_collection
# Purpose: Setup automated evidence collection
setup_evidence_collection() {
    info "Setting up evidence collection"

    # Create evidence collection script
    sudo tee "$EVIDENCE_DIR/collect-evidence.sh" > /dev/null << 'EOF'
#!/bin/bash
# Automated evidence collection for NIST CSF compliance

EVIDENCE_DATE=$(date +%Y%m%d_%H%M%S)
EVIDENCE_ARCHIVE="/var/log/compliance-evidence-${EVIDENCE_DATE}.tar.gz"

# Collect system configuration evidence
mkdir -p /tmp/evidence/system
cp /etc/passwd /tmp/evidence/system/ 2>/dev/null || true
cp /etc/group /tmp/evidence/system/ 2>/dev/null || true
ls -la /etc/ssh/ > /tmp/evidence/system/ssh_config.txt 2>/dev/null || true

# Collect security configuration evidence
mkdir -p /tmp/evidence/security
cp -r /etc/security /tmp/evidence/security/ 2>/dev/null || true
cp -r ~/.password-store /tmp/evidence/security/ 2>/dev/null || true

# Collect audit logs
mkdir -p /tmp/evidence/logs
cp /var/log/auth.log /tmp/evidence/logs/ 2>/dev/null || true
cp /var/log/security-audit/* /tmp/evidence/logs/ 2>/dev/null || true

# Create archive
tar -czf "$EVIDENCE_ARCHIVE" -C /tmp evidence/
rm -rf /tmp/evidence

echo "Evidence collected: $EVIDENCE_ARCHIVE"
EOF

    sudo chmod 755 "$EVIDENCE_DIR/collect-evidence.sh"
}

# Function: assess_control_implementation
# Purpose: Assess implementation status of a specific control
# Args: $1 - function (e.g., "identify"), $2 - category (e.g., "ID.AM"), $3 - control (e.g., "ID.AM-1")
assess_control_implementation() {
    local function="$1"
    local category="$2"
    local control="$3"

    # Get control details from mapping
    local control_data
    control_data=$(jq -r ".functions.$function.$category.controls[\"$control\"]" "$NIST_MAPPING_FILE" 2>/dev/null || echo "null")

    if [[ "$control_data" == "null" ]]; then
        warn "Control not found: $control"
        return 1
    fi

    local description
    description=$(echo "$control_data" | jq -r '.description')
    local status
    status=$(echo "$control_data" | jq -r '.implementation_status')
    local features
    features=$(echo "$control_data" | jq -r '.machine_rites_features[]' 2>/dev/null || echo "")

    echo "=== Control Assessment: $control ==="
    echo "Description: $description"
    echo "Status: $status"
    echo "Machine-rites features:"
    echo "$features" | while read -r feature; do
        if [[ -n "$feature" ]]; then
            echo "  - $feature"
            # Verify feature exists
            verify_feature_implementation "$feature"
        fi
    done
    echo
}

# Function: verify_feature_implementation
# Purpose: Verify that a machine-rites feature is actually implemented
# Args: $1 - feature description
verify_feature_implementation() {
    local feature="$1"

    # Extract file path from feature description
    local file_path
    file_path=$(echo "$feature" | awk '{print $1}' | tr -d '-')

    # Check if file exists
    if [[ -f "$SCRIPT_DIR/../../$file_path" ]] || [[ -f "/home/william/git/machine-rites/$file_path" ]]; then
        echo "    ✓ Implemented"
    else
        echo "    ✗ Missing implementation"
    fi
}

# Function: generate_compliance_report
# Purpose: Generate comprehensive compliance report
# Args: $1 - report format (html|json|markdown)
generate_compliance_report() {
    local format="${1:-html}"
    local timestamp="$(date +%Y%m%d_%H%M%S)"
    local report_file="$REPORTS_DIR/nist-csf-compliance-${timestamp}.$format"

    info "Generating NIST CSF compliance report: $format"

    case "$format" in
        json)
            generate_json_report > "$report_file"
            ;;
        markdown)
            generate_markdown_report > "$report_file"
            ;;
        html)
            generate_html_report > "$report_file"
            ;;
        *)
            die "Unsupported report format: $format"
            ;;
    esac

    ok "Compliance report generated: $report_file"
    echo "$report_file"
}

# Function: generate_json_report
# Purpose: Generate JSON format compliance report
generate_json_report() {
    local assessment_data="{}"
    local total_controls=0
    local implemented=0
    local partial=0
    local not_implemented=0

    # Assess all controls
    jq -r '.functions | to_entries[] | "\(.key) \(.value | to_entries[] | "\(.key) \(.value.controls | keys[])")"' "$NIST_MAPPING_FILE" | \
    while read -r function category control; do
        local status
        status=$(jq -r ".functions.$function.$category.controls[\"$control\"].implementation_status" "$NIST_MAPPING_FILE")

        ((total_controls++))
        case "$status" in
            implemented) ((implemented++)) ;;
            partially_implemented) ((partial++)) ;;
            not_implemented) ((not_implemented++)) ;;
        esac
    done

    # Generate summary JSON
    jq -n \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg total "$total_controls" \
        --arg implemented "$implemented" \
        --arg partial "$partial" \
        --arg not_implemented "$not_implemented" \
        --argjson mappings "$(cat "$NIST_MAPPING_FILE")" \
        '{
            "report_metadata": {
                "generated": $timestamp,
                "framework": "NIST CSF 2.0",
                "organization": "machine-rites",
                "report_type": "compliance_assessment"
            },
            "summary": {
                "total_controls": ($total | tonumber),
                "implemented": ($implemented | tonumber),
                "partially_implemented": ($partial | tonumber),
                "not_implemented": ($not_implemented | tonumber),
                "compliance_percentage": (($implemented | tonumber) * 100 / ($total | tonumber) | floor)
            },
            "detailed_mappings": $mappings
        }'
}

# Function: generate_markdown_report
# Purpose: Generate Markdown format compliance report
generate_markdown_report() {
    cat << EOF
# NIST Cybersecurity Framework Compliance Report

**Generated:** $(date)
**Framework:** NIST CSF 2.0
**Organization:** machine-rites

## Executive Summary

The machine-rites project implements security controls aligned with the NIST Cybersecurity Framework 2.0. This report provides a comprehensive assessment of control implementation status.

### Compliance Overview

$(generate_compliance_summary_markdown)

## Detailed Control Assessment

### IDENTIFY Function

$(assess_function_markdown "identify")

### PROTECT Function

$(assess_function_markdown "protect")

### DETECT Function

$(assess_function_markdown "detect")

### RESPOND Function

$(assess_function_markdown "respond")

### RECOVER Function

$(assess_function_markdown "recover")

## Recommendations

$(generate_recommendations_markdown)

## Evidence Artifacts

- System configuration files
- Security policy documentation
- Audit logs and monitoring data
- Implementation code and scripts
- Test results and validation reports

---
*Report generated by machine-rites NIST CSF compliance system*
EOF
}

# Function: generate_compliance_summary_markdown
# Purpose: Generate compliance summary for markdown report
generate_compliance_summary_markdown() {
    local total=0
    local implemented=0
    local partial=0
    local not_implemented=0

    # Count controls by status
    while read -r status; do
        ((total++))
        case "$status" in
            implemented) ((implemented++)) ;;
            partially_implemented) ((partial++)) ;;
            not_implemented) ((not_implemented++)) ;;
        esac
    done < <(jq -r '.functions[][] | select(.controls) | .controls[].implementation_status' "$NIST_MAPPING_FILE" 2>/dev/null || echo "")

    local compliance_percentage=$((implemented * 100 / total))

    cat << EOF
| Metric | Value |
|--------|-------|
| Total Controls | $total |
| Implemented | $implemented |
| Partially Implemented | $partial |
| Not Implemented | $not_implemented |
| **Compliance Percentage** | **${compliance_percentage}%** |
EOF
}

# Function: assess_function_markdown
# Purpose: Assess a CSF function for markdown report
# Args: $1 - function name
assess_function_markdown() {
    local function="$1"

    echo "#### $function Function"
    echo

    jq -r ".functions.$function | to_entries[] | \"\(.key): \(.value.name) - \(.value.description)\"" "$NIST_MAPPING_FILE" | \
    while IFS=': ' read -r category name_desc; do
        echo "**$category:** $name_desc"
        echo

        # List controls for this category
        jq -r ".functions.$function.$category.controls | to_entries[] | \"- \(.key): \(.value.implementation_status) - \(.value.description)\"" "$NIST_MAPPING_FILE" | \
        while read -r control_line; do
            echo "$control_line"
        done
        echo
    done
}

# Function: generate_recommendations_markdown
# Purpose: Generate recommendations section for markdown report
generate_recommendations_markdown() {
    cat << EOF
### High Priority

1. **Complete Network Monitoring Implementation**
   - Enhance network baseline establishment (DE.AE-1)
   - Implement comprehensive network anomaly detection

2. **Strengthen Data-in-Transit Protection**
   - Implement TLS enforcement across all communications
   - Add certificate management procedures

### Medium Priority

1. **Enhance Documentation**
   - Create comprehensive incident response procedures
   - Document recovery testing procedures

2. **Automate Compliance Monitoring**
   - Implement continuous compliance monitoring
   - Create automated control testing

### Low Priority

1. **Improve Reporting**
   - Add executive dashboard for compliance metrics
   - Implement trend analysis for security controls
EOF
}

# Function: generate_html_report
# Purpose: Generate HTML format compliance report
generate_html_report() {
    cat << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>NIST CSF Compliance Report - machine-rites</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; line-height: 1.6; }
        .header { background-color: #f4f4f4; padding: 20px; border-radius: 5px; }
        .summary { background-color: #e8f5e8; padding: 15px; margin: 20px 0; border-radius: 5px; }
        .function { margin: 20px 0; border: 1px solid #ddd; border-radius: 5px; }
        .function-header { background-color: #f8f9fa; padding: 10px; font-weight: bold; }
        .control { margin: 10px; padding: 10px; background-color: #fafafa; }
        .implemented { border-left: 4px solid #28a745; }
        .partial { border-left: 4px solid #ffc107; }
        .not-implemented { border-left: 4px solid #dc3545; }
        .metric { display: inline-block; margin: 10px; padding: 10px; background-color: #fff; border: 1px solid #ddd; border-radius: 3px; }
        table { border-collapse: collapse; width: 100%; margin: 20px 0; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
    </style>
</head>
<body>
    <div class="header">
        <h1>NIST Cybersecurity Framework Compliance Report</h1>
        <p><strong>Generated:</strong> $(date)</p>
        <p><strong>Framework:</strong> NIST CSF 2.0</p>
        <p><strong>Organization:</strong> machine-rites</p>
    </div>

    <div class="summary">
        <h2>Executive Summary</h2>
        <p>This report provides a comprehensive assessment of machine-rites compliance with NIST Cybersecurity Framework 2.0 controls.</p>

        <div class="metrics">
EOF

    # Add dynamic compliance metrics
    generate_html_metrics

    cat << 'EOF'
        </div>
    </div>

    <h2>Detailed Assessment</h2>
EOF

    # Add detailed function assessments
    generate_html_functions

    cat << 'EOF'

    <h2>Implementation Evidence</h2>
    <p>The following machine-rites components provide evidence of control implementation:</p>
    <ul>
        <li><strong>Bootstrap System:</strong> Automated system hardening and configuration</li>
        <li><strong>Security Framework:</strong> Audit logging, intrusion detection, and compliance monitoring</li>
        <li><strong>Secret Management:</strong> GPG-based encryption and automated rotation</li>
        <li><strong>Access Control:</strong> SSH key management and secure authentication</li>
        <li><strong>Monitoring:</strong> Real-time security monitoring and alerting</li>
    </ul>

    <footer style="margin-top: 40px; padding-top: 20px; border-top: 1px solid #ddd; color: #666;">
        <p><em>Report generated by machine-rites NIST CSF compliance system</em></p>
    </footer>
</body>
</html>
EOF
}

# Function: generate_html_metrics
# Purpose: Generate HTML metrics section
generate_html_metrics() {
    local total=0
    local implemented=0
    local partial=0
    local not_implemented=0

    # Count implementation status
    while read -r status; do
        ((total++))
        case "$status" in
            implemented) ((implemented++)) ;;
            partially_implemented) ((partial++)) ;;
            not_implemented) ((not_implemented++)) ;;
        esac
    done < <(jq -r '.functions[][] | select(.controls) | .controls[].implementation_status' "$NIST_MAPPING_FILE" 2>/dev/null || echo "")

    local compliance_percentage=$((implemented * 100 / total))

    cat << EOF
            <div class="metric">
                <h3>$total</h3>
                <p>Total Controls</p>
            </div>
            <div class="metric">
                <h3>$implemented</h3>
                <p>Implemented</p>
            </div>
            <div class="metric">
                <h3>$partial</h3>
                <p>Partial</p>
            </div>
            <div class="metric">
                <h3>$not_implemented</h3>
                <p>Not Implemented</p>
            </div>
            <div class="metric">
                <h3>${compliance_percentage}%</h3>
                <p>Compliance</p>
            </div>
EOF
}

# Function: generate_html_functions
# Purpose: Generate HTML functions section
generate_html_functions() {
    # This would generate detailed HTML for each CSF function
    # For brevity, showing structure only

    local functions=("identify" "protect" "detect" "respond" "recover")

    for function in "${functions[@]}"; do
        echo "<div class='function'>"
        echo "<div class='function-header'>$(echo "$function" | tr '[:lower:]' '[:upper:]') Function</div>"

        # Add controls for this function
        jq -r ".functions.$function | to_entries[] | \"\(.key)\"" "$NIST_MAPPING_FILE" 2>/dev/null | \
        while read -r category; do
            jq -r ".functions.$function.$category.controls | to_entries[] | \"\(.key) \(.value.implementation_status) \(.value.description)\"" "$NIST_MAPPING_FILE" 2>/dev/null | \
            while read -r control status description; do
                local css_class
                case "$status" in
                    implemented) css_class="implemented" ;;
                    partially_implemented) css_class="partial" ;;
                    not_implemented) css_class="not-implemented" ;;
                esac

                echo "<div class='control $css_class'>"
                echo "<strong>$control:</strong> $description"
                echo "<br><em>Status: $status</em>"
                echo "</div>"
            done
        done

        echo "</div>"
    done
}

# Function: run_compliance_assessment
# Purpose: Run complete compliance assessment
run_compliance_assessment() {
    info "Running comprehensive NIST CSF compliance assessment"

    # Collect evidence
    "$EVIDENCE_DIR/collect-evidence.sh"

    # Generate reports in all formats
    local json_report
    json_report=$(generate_compliance_report "json")
    local markdown_report
    markdown_report=$(generate_compliance_report "markdown")
    local html_report
    html_report=$(generate_compliance_report "html")

    # Generate summary
    echo
    echo "=== NIST CSF Compliance Assessment Complete ==="
    echo "Reports generated:"
    echo "  JSON: $json_report"
    echo "  Markdown: $markdown_report"
    echo "  HTML: $html_report"
    echo

    # Show quick summary
    local compliance_percentage
    compliance_percentage=$(jq -r '.summary.compliance_percentage' "$json_report" 2>/dev/null || echo "0")
    echo "Overall Compliance: ${compliance_percentage}%"

    if [[ $compliance_percentage -ge 80 ]]; then
        ok "Strong compliance posture"
    elif [[ $compliance_percentage -ge 60 ]]; then
        warn "Moderate compliance, improvement needed"
    else
        fail "Low compliance, significant gaps identified"
    fi
}

# Function: main
# Purpose: Main entry point
main() {
    local action="${1:-}"

    case "$action" in
        init)
            init_nist_compliance
            ;;
        assess)
            shift
            if [[ $# -eq 3 ]]; then
                assess_control_implementation "$@"
            else
                run_compliance_assessment
            fi
            ;;
        report)
            shift
            generate_compliance_report "$@"
            ;;
        evidence)
            "$EVIDENCE_DIR/collect-evidence.sh"
            ;;
        *)
            echo "Usage: $0 {init|assess|report|evidence}"
            echo "  init                    - Initialize NIST CSF compliance system"
            echo "  assess [func cat ctrl]  - Assess specific control or run full assessment"
            echo "  report [format]         - Generate compliance report (html|json|markdown)"
            echo "  evidence                - Collect compliance evidence"
            exit 1
            ;;
    esac
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi