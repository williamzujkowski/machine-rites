#!/usr/bin/env bash
# security/gpg-backup-restore.sh - Comprehensive GPG Key Backup and Restore System
#
# Description: Secure GPG key management with automated backup and restore
# Version: 1.0.0
# Dependencies: gpg, pass, lib/validation.sh, lib/common.sh
# Security: Air-gapped backup support, encrypted storage, integrity validation
#
# Features:
#   - Automated GPG key backup with versioning
#   - Secure restore operations with verification
#   - Paper backup generation for air-gapped storage
#   - Key rotation and migration support
#   - Integrity checking and validation

set -euo pipefail

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=../lib/validation.sh
source "$SCRIPT_DIR/../lib/validation.sh"
# shellcheck source=audit/audit-logger.sh
source "$SCRIPT_DIR/audit/audit-logger.sh"

# Configuration
readonly GPG_BACKUP_DIR="/var/backups/gpg-keys"
readonly GPG_RESTORE_DIR="/tmp/gpg-restore"
readonly BACKUP_ENCRYPTION_KEY="backup@machine-rites.local"
readonly PAPER_BACKUP_DIR="/var/backups/paper-keys"
readonly MAX_BACKUP_VERSIONS=10

# Secure permissions
umask 077

# Function: init_gpg_backup_system
# Purpose: Initialize GPG backup and restore system
init_gpg_backup_system() {
    info "Initializing GPG backup and restore system"

    # Create backup directories with secure permissions
    sudo mkdir -p "$GPG_BACKUP_DIR" "$PAPER_BACKUP_DIR"
    sudo chmod 700 "$GPG_BACKUP_DIR" "$PAPER_BACKUP_DIR"

    # Create restore directory (temporary)
    mkdir -p "$GPG_RESTORE_DIR"
    chmod 700 "$GPG_RESTORE_DIR"

    # Generate backup encryption key if it doesn't exist
    if ! gpg --list-keys "$BACKUP_ENCRYPTION_KEY" >/dev/null 2>&1; then
        generate_backup_encryption_key
    fi

    # Create backup configuration
    create_backup_config

    ok "GPG backup system initialized"
}

# Function: generate_backup_encryption_key
# Purpose: Generate dedicated key for backup encryption
generate_backup_encryption_key() {
    info "Generating backup encryption key"

    # Create key generation configuration
    local key_config
    key_config=$(mktemp)

    cat > "$key_config" << EOF
%echo Generating GPG backup encryption key
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Real: Machine Rites Backup System
Name-Email: $BACKUP_ENCRYPTION_KEY
Expire-Date: 2y
Preferences: SHA512 SHA384 SHA256 AES256 AES192 AES ZLIB BZIP2 ZIP Uncompressed
%commit
%echo Backup encryption key generation complete
EOF

    # Generate key
    gpg --batch --generate-key "$key_config"

    # Clean up
    rm -f "$key_config"

    log_audit_event "GPG_BACKUP" "ENCRYPTION_KEY_GENERATED" "INFO" "Backup encryption key generated" \
                   '{"key_email": "'$BACKUP_ENCRYPTION_KEY'"}'
}

# Function: create_backup_config
# Purpose: Create backup configuration file
create_backup_config() {
    local config_file="$GPG_BACKUP_DIR/backup-config.json"

    sudo tee "$config_file" > /dev/null << EOF
{
    "backup_system": {
        "version": "1.0.0",
        "encryption_key": "$BACKUP_ENCRYPTION_KEY",
        "max_versions": $MAX_BACKUP_VERSIONS,
        "compression": true,
        "integrity_checks": true
    },
    "backup_schedule": {
        "automatic": false,
        "frequency": "weekly",
        "retention_months": 12
    },
    "backup_types": {
        "full": {
            "description": "Complete GPG keyring backup",
            "includes": ["public_keys", "secret_keys", "trust_db", "configuration"]
        },
        "secrets_only": {
            "description": "Secret keys only",
            "includes": ["secret_keys"]
        },
        "public_only": {
            "description": "Public keys only",
            "includes": ["public_keys", "trust_db"]
        }
    },
    "paper_backup": {
        "enabled": true,
        "format": "qr_code",
        "split_threshold": 2048,
        "redundancy": 3
    }
}
EOF

    sudo chmod 600 "$config_file"
}

# Function: backup_gpg_keys
# Purpose: Create comprehensive GPG key backup
# Args: $1 - backup type (full|secrets_only|public_only), $2 - destination (optional)
backup_gpg_keys() {
    local backup_type="${1:-full}"
    local destination="${2:-$GPG_BACKUP_DIR}"
    local timestamp="$(date +%Y%m%d_%H%M%S)"
    local backup_name="gpg-${backup_type}-backup-${timestamp}"

    info "Creating GPG backup: $backup_type"

    # Validate backup type
    case "$backup_type" in
        full|secrets_only|public_only) ;;
        *) die "Invalid backup type: $backup_type" ;;
    esac

    # Create temporary backup directory
    local temp_backup_dir
    temp_backup_dir="$(mktemp -d)"
    chmod 700 "$temp_backup_dir"

    # Export keys based on backup type
    case "$backup_type" in
        full)
            export_full_backup "$temp_backup_dir"
            ;;
        secrets_only)
            export_secret_keys_only "$temp_backup_dir"
            ;;
        public_only)
            export_public_keys_only "$temp_backup_dir"
            ;;
    esac

    # Create backup metadata
    create_backup_metadata "$temp_backup_dir" "$backup_type"

    # Create encrypted archive
    local backup_archive="$destination/${backup_name}.tar.gpg"
    create_encrypted_backup_archive "$temp_backup_dir" "$backup_archive"

    # Generate integrity checksums
    generate_backup_checksums "$backup_archive"

    # Create paper backup if enabled and type is full or secrets_only
    if [[ "$backup_type" == "full" ]] || [[ "$backup_type" == "secrets_only" ]]; then
        create_paper_backup "$temp_backup_dir" "$backup_name"
    fi

    # Clean up temporary directory
    rm -rf "$temp_backup_dir"

    # Cleanup old backups
    cleanup_old_backups "$destination"

    log_audit_event "GPG_BACKUP" "BACKUP_CREATED" "INFO" "GPG backup created" \
                   '{"backup_type": "'$backup_type'", "backup_file": "'$backup_archive'", "timestamp": "'$timestamp'"}'

    ok "GPG backup created: $backup_archive"
    echo "$backup_archive"
}

# Function: export_full_backup
# Purpose: Export complete GPG keyring
# Args: $1 - destination directory
export_full_backup() {
    local dest_dir="$1"

    info "Exporting complete GPG keyring"

    # Export all public keys
    gpg --export --armor > "$dest_dir/public-keys.asc"

    # Export all secret keys
    gpg --export-secret-keys --armor > "$dest_dir/secret-keys.asc"

    # Export trust database
    gpg --export-ownertrust > "$dest_dir/trust-db.txt"

    # Export GPG configuration
    if [[ -f "$HOME/.gnupg/gpg.conf" ]]; then
        cp "$HOME/.gnupg/gpg.conf" "$dest_dir/"
    fi

    # Export key preferences
    gpg --list-keys --with-colons > "$dest_dir/key-list.txt"
    gpg --list-secret-keys --with-colons > "$dest_dir/secret-key-list.txt"

    # Export revocation certificates if they exist
    if [[ -d "$HOME/.gnupg/openpgp-revocs.d" ]]; then
        cp -r "$HOME/.gnupg/openpgp-revocs.d" "$dest_dir/" 2>/dev/null || true
    fi
}

# Function: export_secret_keys_only
# Purpose: Export only secret keys
# Args: $1 - destination directory
export_secret_keys_only() {
    local dest_dir="$1"

    info "Exporting secret keys only"

    # Export all secret keys
    gpg --export-secret-keys --armor > "$dest_dir/secret-keys.asc"

    # Export list of secret keys
    gpg --list-secret-keys --with-colons > "$dest_dir/secret-key-list.txt"
}

# Function: export_public_keys_only
# Purpose: Export only public keys and trust database
# Args: $1 - destination directory
export_public_keys_only() {
    local dest_dir="$1"

    info "Exporting public keys and trust database"

    # Export all public keys
    gpg --export --armor > "$dest_dir/public-keys.asc"

    # Export trust database
    gpg --export-ownertrust > "$dest_dir/trust-db.txt"

    # Export list of public keys
    gpg --list-keys --with-colons > "$dest_dir/key-list.txt"
}

# Function: create_backup_metadata
# Purpose: Create comprehensive backup metadata
# Args: $1 - backup directory, $2 - backup type
create_backup_metadata() {
    local backup_dir="$1"
    local backup_type="$2"

    local metadata_file="$backup_dir/backup-metadata.json"

    # Get GPG version and configuration info
    local gpg_version
    gpg_version="$(gpg --version | head -n1)"

    # Get key statistics
    local public_keys
    public_keys="$(gpg --list-keys --with-colons | grep -c '^pub:' || echo '0')"
    local secret_keys
    secret_keys="$(gpg --list-secret-keys --with-colons | grep -c '^sec:' || echo '0')"

    # Get system information
    local hostname
    hostname="$(hostname)"
    local username
    username="$(whoami)"

    cat > "$metadata_file" << EOF
{
    "backup_metadata": {
        "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
        "backup_type": "$backup_type",
        "version": "1.0.0",
        "creator": "$username@$hostname"
    },
    "system_info": {
        "hostname": "$hostname",
        "username": "$username",
        "gpg_version": "$gpg_version",
        "os_version": "$(uname -a)"
    },
    "key_statistics": {
        "public_keys": $public_keys,
        "secret_keys": $secret_keys,
        "total_keys": $((public_keys + secret_keys))
    },
    "backup_contents": {
        "public_keys": $([ -f "$backup_dir/public-keys.asc" ] && echo "true" || echo "false"),
        "secret_keys": $([ -f "$backup_dir/secret-keys.asc" ] && echo "true" || echo "false"),
        "trust_db": $([ -f "$backup_dir/trust-db.txt" ] && echo "true" || echo "false"),
        "configuration": $([ -f "$backup_dir/gpg.conf" ] && echo "true" || echo "false"),
        "revocation_certs": $([ -d "$backup_dir/openpgp-revocs.d" ] && echo "true" || echo "false")
    },
    "integrity": {
        "checksums": {},
        "verification_required": true
    }
}
EOF

    # Generate checksums for all files
    for file in "$backup_dir"/*.asc "$backup_dir"/*.txt "$backup_dir"/gpg.conf; do
        if [[ -f "$file" ]]; then
            local filename
            filename="$(basename "$file")"
            local checksum
            checksum="$(sha256sum "$file" | cut -d' ' -f1)"

            # Update metadata with checksum
            jq --arg filename "$filename" --arg checksum "$checksum" \
               '.integrity.checksums[$filename] = $checksum' \
               "$metadata_file" > "$metadata_file.tmp" && mv "$metadata_file.tmp" "$metadata_file"
        fi
    done
}

# Function: create_encrypted_backup_archive
# Purpose: Create encrypted and compressed backup archive
# Args: $1 - source directory, $2 - destination archive
create_encrypted_backup_archive() {
    local source_dir="$1"
    local dest_archive="$2"

    info "Creating encrypted backup archive"

    # Create compressed tar archive and encrypt with GPG
    (cd "$(dirname "$source_dir")" && tar -czf - "$(basename "$source_dir")") | \
        gpg --cipher-algo AES256 --compress-algo 2 --symmetric \
            --recipient "$BACKUP_ENCRYPTION_KEY" \
            --output "$dest_archive" --armor --yes --quiet

    # Verify archive was created
    if [[ ! -f "$dest_archive" ]]; then
        die "Failed to create backup archive: $dest_archive"
    fi

    # Set secure permissions
    sudo chmod 600 "$dest_archive"
}

# Function: generate_backup_checksums
# Purpose: Generate integrity checksums for backup
# Args: $1 - backup archive file
generate_backup_checksums() {
    local backup_file="$1"
    local checksum_file="${backup_file}.sha256"

    info "Generating backup integrity checksums"

    # Generate SHA256 checksum
    sha256sum "$backup_file" | sudo tee "$checksum_file" > /dev/null

    # Generate SHA512 checksum for extra security
    sha512sum "$backup_file" | sudo tee "${backup_file}.sha512" > /dev/null

    # Set secure permissions
    sudo chmod 600 "$checksum_file" "${backup_file}.sha512"
}

# Function: create_paper_backup
# Purpose: Create paper backup for air-gapped storage
# Args: $1 - backup directory, $2 - backup name
create_paper_backup() {
    local backup_dir="$1"
    local backup_name="$2"

    info "Creating paper backup for air-gapped storage"

    local paper_dir="$PAPER_BACKUP_DIR/$backup_name"
    sudo mkdir -p "$paper_dir"
    sudo chmod 700 "$paper_dir"

    # Create QR codes for secret keys if qrencode is available
    if command -v qrencode >/dev/null 2>&1 && [[ -f "$backup_dir/secret-keys.asc" ]]; then
        info "Generating QR codes for secret keys"

        # Split large files for QR code generation
        split -b 2048 "$backup_dir/secret-keys.asc" "$paper_dir/secret-keys-part-"

        # Generate QR codes for each part
        local part_number=1
        for part_file in "$paper_dir"/secret-keys-part-*; do
            if [[ -f "$part_file" ]]; then
                qrencode -o "$paper_dir/secret-keys-qr-${part_number}.png" \
                         -t PNG -s 3 -l H < "$part_file"
                ((part_number++))
            fi
        done

        # Create assembly instructions
        cat > "$paper_dir/assembly-instructions.txt" << EOF
Paper Backup Assembly Instructions
==================================

Backup Name: $backup_name
Created: $(date)
Parts: $((part_number - 1))

To restore from paper backup:
1. Scan all QR codes in sequence
2. Concatenate the decoded text files in order
3. Save as secret-keys.asc
4. Import with: gpg --import secret-keys.asc

Verification:
- Each part should be exactly 2048 bytes (except possibly the last)
- The final reassembled file should match the original SHA256 sum

Security Notes:
- Store parts in separate secure locations
- Consider using a bank safety deposit box
- Keep assembly instructions separate from QR codes
EOF

        sudo chown -R root:root "$paper_dir"
        sudo chmod -R 600 "$paper_dir"/*

        ok "Paper backup created with $((part_number - 1)) QR code parts"
    else
        warn "qrencode not available - creating text-only paper backup"

        # Create simplified text backup
        if [[ -f "$backup_dir/secret-keys.asc" ]]; then
            sudo cp "$backup_dir/secret-keys.asc" "$paper_dir/"
            sudo chmod 600 "$paper_dir/secret-keys.asc"
        fi
    fi

    log_audit_event "GPG_BACKUP" "PAPER_BACKUP_CREATED" "INFO" "Paper backup created" \
                   '{"backup_name": "'$backup_name'", "paper_dir": "'$paper_dir'"}'
}

# Function: cleanup_old_backups
# Purpose: Remove old backup files beyond retention limit
# Args: $1 - backup directory
cleanup_old_backups() {
    local backup_dir="$1"

    info "Cleaning up old backups (keeping $MAX_BACKUP_VERSIONS versions)"

    # Find backup files and sort by modification time
    local backup_files
    mapfile -t backup_files < <(find "$backup_dir" -name "gpg-*-backup-*.tar.gpg" -type f -printf '%T@ %p\n' | sort -nr | cut -d' ' -f2-)

    # Remove old backups if we have more than MAX_BACKUP_VERSIONS
    if [[ ${#backup_files[@]} -gt $MAX_BACKUP_VERSIONS ]]; then
        local files_to_remove=("${backup_files[@]:$MAX_BACKUP_VERSIONS}")

        for file in "${files_to_remove[@]}"; do
            info "Removing old backup: $(basename "$file")"
            sudo rm -f "$file" "${file}.sha256" "${file}.sha512"
        done

        log_audit_event "GPG_BACKUP" "OLD_BACKUPS_CLEANED" "INFO" "Old backups removed" \
                       '{"removed_count": '${#files_to_remove[@]}'}'
    fi
}

# Function: list_backups
# Purpose: List available GPG backups with details
list_backups() {
    info "Available GPG backups:"
    echo

    if [[ ! -d "$GPG_BACKUP_DIR" ]]; then
        warn "Backup directory not found: $GPG_BACKUP_DIR"
        return 1
    fi

    # Find all backup files
    local backup_files
    mapfile -t backup_files < <(find "$GPG_BACKUP_DIR" -name "gpg-*-backup-*.tar.gpg" -type f | sort -r)

    if [[ ${#backup_files[@]} -eq 0 ]]; then
        warn "No backup files found"
        return 1
    fi

    printf "%-40s %-12s %-10s %-20s %s\n" "BACKUP NAME" "TYPE" "SIZE" "DATE" "STATUS"
    printf "%-40s %-12s %-10s %-20s %s\n" \
           "$(printf '%*s' 40 '' | tr ' ' '-')" \
           "$(printf '%*s' 12 '' | tr ' ' '-')" \
           "$(printf '%*s' 10 '' | tr ' ' '-')" \
           "$(printf '%*s' 20 '' | tr ' ' '-')" \
           "$(printf '%*s' 10 '' | tr ' ' '-')"

    for backup_file in "${backup_files[@]}"; do
        local backup_name
        backup_name="$(basename "$backup_file" .tar.gpg)"

        # Extract backup type from filename
        local backup_type
        if [[ "$backup_name" =~ gpg-(.*)-backup-([0-9_]+) ]]; then
            backup_type="${BASH_REMATCH[1]}"
        else
            backup_type="unknown"
        fi

        # Get file size
        local file_size
        file_size="$(du -h "$backup_file" | cut -f1)"

        # Get file date
        local file_date
        file_date="$(stat -c %y "$backup_file" | cut -d' ' -f1)"

        # Check integrity
        local status="UNKNOWN"
        if [[ -f "${backup_file}.sha256" ]]; then
            if sha256sum -c "${backup_file}.sha256" >/dev/null 2>&1; then
                status="OK"
            else
                status="CORRUPTED"
            fi
        fi

        printf "%-40s %-12s %-10s %-20s %s\n" \
               "$backup_name" "$backup_type" "$file_size" "$file_date" "$status"
    done
}

# Function: verify_backup
# Purpose: Verify backup integrity and contents
# Args: $1 - backup file path
verify_backup() {
    local backup_file="$1"

    if [[ ! -f "$backup_file" ]]; then
        die "Backup file not found: $backup_file"
    fi

    info "Verifying backup: $(basename "$backup_file")"

    # Verify checksums
    echo "=== Checksum Verification ==="
    local checksum_verified=false

    if [[ -f "${backup_file}.sha256" ]]; then
        if sha256sum -c "${backup_file}.sha256"; then
            ok "SHA256 checksum verified"
            checksum_verified=true
        else
            fail "SHA256 checksum verification failed"
        fi
    fi

    if [[ -f "${backup_file}.sha512" ]]; then
        if sha512sum -c "${backup_file}.sha512"; then
            ok "SHA512 checksum verified"
            checksum_verified=true
        else
            fail "SHA512 checksum verification failed"
        fi
    fi

    if [[ "$checksum_verified" == "false" ]]; then
        warn "No checksums available for verification"
    fi

    # Verify GPG encryption
    echo
    echo "=== GPG Encryption Verification ==="
    if gpg --quiet --batch --decrypt "$backup_file" >/dev/null 2>&1; then
        ok "GPG decryption test successful"
    else
        fail "GPG decryption test failed"
        return 1
    fi

    # Extract and verify contents
    echo
    echo "=== Content Verification ==="
    local temp_verify_dir
    temp_verify_dir="$(mktemp -d)"
    chmod 700 "$temp_verify_dir"

    if gpg --quiet --batch --decrypt "$backup_file" | tar -xzf - -C "$temp_verify_dir"; then
        ok "Archive extraction successful"

        # Find the extracted directory
        local extracted_dir
        extracted_dir="$(find "$temp_verify_dir" -maxdepth 1 -type d ! -path "$temp_verify_dir" | head -1)"

        if [[ -d "$extracted_dir" ]]; then
            echo "Backup contents:"

            # Check for metadata
            if [[ -f "$extracted_dir/backup-metadata.json" ]]; then
                local backup_type
                backup_type="$(jq -r '.backup_metadata.backup_type' "$extracted_dir/backup-metadata.json")"
                local timestamp
                timestamp="$(jq -r '.backup_metadata.timestamp' "$extracted_dir/backup-metadata.json")"
                local key_count
                key_count="$(jq -r '.key_statistics.total_keys' "$extracted_dir/backup-metadata.json")"

                echo "  - Backup type: $backup_type"
                echo "  - Created: $timestamp"
                echo "  - Total keys: $key_count"
            fi

            # List contents
            for file in "$extracted_dir"/*; do
                if [[ -f "$file" ]]; then
                    local filename
                    filename="$(basename "$file")"
                    local size
                    size="$(du -h "$file" | cut -f1)"
                    echo "  - $filename ($size)"
                fi
            done
        fi
    else
        fail "Archive extraction failed"
    fi

    # Clean up
    rm -rf "$temp_verify_dir"

    log_audit_event "GPG_BACKUP" "BACKUP_VERIFIED" "INFO" "Backup verification completed" \
                   '{"backup_file": "'$backup_file'", "checksum_verified": '$checksum_verified'}'

    ok "Backup verification completed"
}

# Function: restore_gpg_keys
# Purpose: Restore GPG keys from backup
# Args: $1 - backup file path, $2 - restore type (full|secrets_only|public_only)
restore_gpg_keys() {
    local backup_file="$1"
    local restore_type="${2:-full}"

    if [[ ! -f "$backup_file" ]]; then
        die "Backup file not found: $backup_file"
    fi

    info "Restoring GPG keys from backup: $(basename "$backup_file")"

    # Verify backup before restore
    if ! verify_backup "$backup_file"; then
        die "Backup verification failed - aborting restore"
    fi

    # Confirm restore operation
    if [[ -t 1 ]]; then
        echo
        warn "This operation will import keys into your GPG keyring"
        warn "Existing keys with the same ID may be updated"
        read -rp "Continue with restore? [y/N] " -n 1 confirm
        echo

        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            info "Restore operation cancelled"
            return 0
        fi
    fi

    # Create temporary restore directory
    local temp_restore_dir
    temp_restore_dir="$(mktemp -d)"
    chmod 700 "$temp_restore_dir"

    # Extract backup
    info "Extracting backup archive"
    if ! gpg --quiet --batch --decrypt "$backup_file" | tar -xzf - -C "$temp_restore_dir"; then
        rm -rf "$temp_restore_dir"
        die "Failed to extract backup archive"
    fi

    # Find extracted directory
    local extracted_dir
    extracted_dir="$(find "$temp_restore_dir" -maxdepth 1 -type d ! -path "$temp_restore_dir" | head -1)"

    if [[ ! -d "$extracted_dir" ]]; then
        rm -rf "$temp_restore_dir"
        die "Could not find extracted backup directory"
    fi

    # Perform restore based on type
    case "$restore_type" in
        full)
            restore_full_backup "$extracted_dir"
            ;;
        secrets_only)
            restore_secret_keys_only "$extracted_dir"
            ;;
        public_only)
            restore_public_keys_only "$extracted_dir"
            ;;
        *)
            rm -rf "$temp_restore_dir"
            die "Invalid restore type: $restore_type"
            ;;
    esac

    # Clean up
    rm -rf "$temp_restore_dir"

    log_audit_event "GPG_BACKUP" "KEYS_RESTORED" "INFO" "GPG keys restored from backup" \
                   '{"backup_file": "'$backup_file'", "restore_type": "'$restore_type'"}'

    ok "GPG key restore completed successfully"
}

# Function: restore_full_backup
# Purpose: Restore complete GPG keyring from backup
# Args: $1 - extracted backup directory
restore_full_backup() {
    local backup_dir="$1"

    info "Performing full GPG keyring restore"

    # Import public keys
    if [[ -f "$backup_dir/public-keys.asc" ]]; then
        info "Importing public keys"
        if gpg --import "$backup_dir/public-keys.asc"; then
            ok "Public keys imported successfully"
        else
            warn "Some public keys may have failed to import"
        fi
    fi

    # Import secret keys
    if [[ -f "$backup_dir/secret-keys.asc" ]]; then
        info "Importing secret keys"
        if gpg --import "$backup_dir/secret-keys.asc"; then
            ok "Secret keys imported successfully"
        else
            warn "Some secret keys may have failed to import"
        fi
    fi

    # Restore trust database
    if [[ -f "$backup_dir/trust-db.txt" ]]; then
        info "Restoring trust database"
        if gpg --import-ownertrust "$backup_dir/trust-db.txt"; then
            ok "Trust database restored successfully"
        else
            warn "Trust database restore may have failed"
        fi
    fi

    # Restore GPG configuration
    if [[ -f "$backup_dir/gpg.conf" ]]; then
        info "Restoring GPG configuration"
        if [[ -f "$HOME/.gnupg/gpg.conf" ]]; then
            cp "$HOME/.gnupg/gpg.conf" "$HOME/.gnupg/gpg.conf.backup.$(date +%Y%m%d_%H%M%S)"
        fi
        cp "$backup_dir/gpg.conf" "$HOME/.gnupg/"
        chmod 600 "$HOME/.gnupg/gpg.conf"
        ok "GPG configuration restored"
    fi

    # Restore revocation certificates
    if [[ -d "$backup_dir/openpgp-revocs.d" ]]; then
        info "Restoring revocation certificates"
        mkdir -p "$HOME/.gnupg/openpgp-revocs.d"
        cp -r "$backup_dir/openpgp-revocs.d"/* "$HOME/.gnupg/openpgp-revocs.d/" 2>/dev/null || true
        chmod 700 "$HOME/.gnupg/openpgp-revocs.d"
        chmod 600 "$HOME/.gnupg/openpgp-revocs.d"/* 2>/dev/null || true
        ok "Revocation certificates restored"
    fi
}

# Function: restore_secret_keys_only
# Purpose: Restore only secret keys from backup
# Args: $1 - extracted backup directory
restore_secret_keys_only() {
    local backup_dir="$1"

    info "Restoring secret keys only"

    if [[ -f "$backup_dir/secret-keys.asc" ]]; then
        if gpg --import "$backup_dir/secret-keys.asc"; then
            ok "Secret keys imported successfully"
        else
            warn "Some secret keys may have failed to import"
        fi
    else
        die "Secret keys file not found in backup"
    fi
}

# Function: restore_public_keys_only
# Purpose: Restore only public keys and trust database
# Args: $1 - extracted backup directory
restore_public_keys_only() {
    local backup_dir="$1"

    info "Restoring public keys and trust database"

    # Import public keys
    if [[ -f "$backup_dir/public-keys.asc" ]]; then
        if gpg --import "$backup_dir/public-keys.asc"; then
            ok "Public keys imported successfully"
        else
            warn "Some public keys may have failed to import"
        fi
    else
        die "Public keys file not found in backup"
    fi

    # Restore trust database
    if [[ -f "$backup_dir/trust-db.txt" ]]; then
        if gpg --import-ownertrust "$backup_dir/trust-db.txt"; then
            ok "Trust database restored successfully"
        else
            warn "Trust database restore may have failed"
        fi
    fi
}

# Function: migrate_gpg_keys
# Purpose: Migrate GPG keys between systems or formats
# Args: $1 - migration type (system|format), $2 - source, $3 - destination
migrate_gpg_keys() {
    local migration_type="$1"
    local source="$2"
    local destination="$3"

    info "Starting GPG key migration: $migration_type"

    case "$migration_type" in
        system)
            migrate_between_systems "$source" "$destination"
            ;;
        format)
            migrate_key_format "$source" "$destination"
            ;;
        *)
            die "Invalid migration type: $migration_type"
            ;;
    esac

    log_audit_event "GPG_BACKUP" "KEY_MIGRATION" "INFO" "GPG key migration completed" \
                   '{"migration_type": "'$migration_type'", "source": "'$source'", "destination": "'$destination'"}'
}

# Function: migrate_between_systems
# Purpose: Migrate GPG keys between different systems
# Args: $1 - source system identifier, $2 - destination system identifier
migrate_between_systems() {
    local source="$1"
    local destination="$2"

    info "Migrating GPG keys from $source to $destination"

    # Create migration backup
    local migration_backup
    migration_backup="$(backup_gpg_keys "full" "/tmp")"

    info "Migration backup created: $migration_backup"
    info "Transfer this file to the destination system and use the restore function"

    echo
    echo "Migration Instructions:"
    echo "1. Securely transfer: $migration_backup"
    echo "2. On destination system, run:"
    echo "   $0 restore '$migration_backup'"
    echo "3. Verify keys after import"
    echo "4. Securely delete backup file after successful migration"
}

# Function: main
# Purpose: Main entry point
main() {
    local action="${1:-}"

    case "$action" in
        init)
            init_gpg_backup_system
            ;;
        backup)
            shift
            backup_gpg_keys "$@"
            ;;
        restore)
            shift
            restore_gpg_keys "$@"
            ;;
        list)
            list_backups
            ;;
        verify)
            shift
            verify_backup "$@"
            ;;
        migrate)
            shift
            migrate_gpg_keys "$@"
            ;;
        *)
            echo "Usage: $0 {init|backup|restore|list|verify|migrate}"
            echo
            echo "COMMANDS:"
            echo "  init                           - Initialize GPG backup system"
            echo "  backup [type] [destination]    - Create GPG backup (full|secrets_only|public_only)"
            echo "  restore <file> [type]          - Restore from backup (full|secrets_only|public_only)"
            echo "  list                           - List available backups"
            echo "  verify <file>                  - Verify backup integrity"
            echo "  migrate <type> <src> <dest>    - Migrate keys (system|format)"
            echo
            echo "EXAMPLES:"
            echo "  $0 backup full"
            echo "  $0 backup secrets_only /media/usb"
            echo "  $0 restore /var/backups/gpg-keys/gpg-full-backup-20240101_120000.tar.gpg"
            echo "  $0 verify /var/backups/gpg-keys/gpg-full-backup-20240101_120000.tar.gpg"
            echo "  $0 migrate system old-laptop new-laptop"
            exit 1
            ;;
    esac
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi