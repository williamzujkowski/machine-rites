#!/usr/bin/env bash
# Multipass VM Testing Infrastructure for machine-rites
# Provides automated testing across multiple Ubuntu versions

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
readonly VM_PREFIX="rites"
readonly DEFAULT_CPUS=2
readonly DEFAULT_MEMORY="2G"
readonly DEFAULT_DISK="10G"

# VM configurations
declare -A VM_CONFIGS=(
    ["2204"]="22.04:ubuntu-2204:Ubuntu 22.04 LTS"
    ["2404"]="24.04:ubuntu-2404:Ubuntu 24.04 LTS"
    ["2004"]="20.04:ubuntu-2004:Ubuntu 20.04 LTS"
)

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Check if multipass is available with validation
check_multipass() {
    if ! command -v multipass >/dev/null 2>&1; then
        log_error "Multipass is not installed"
        log_info "Install with: snap install multipass"
        log_info "Or visit: https://multipass.run/install"
        log_info "Falling back to Docker if available"
        return 1
    fi

    # Validate multipass is actually working
    if ! multipass version >/dev/null 2>&1; then
        log_error "Multipass is installed but not responding"
        log_info "Try: sudo snap restart multipass"
        log_info "Or: sudo snap connect multipass:home"

        # Attempt to fix common issues
        if command -v snap >/dev/null 2>&1; then
            log_info "Attempting to restart multipass service..."
            sudo snap restart multipass 2>/dev/null || true
            sleep 2

            # Check again after restart
            if multipass version >/dev/null 2>&1; then
                log_success "Multipass service restarted successfully"
            else
                log_error "Multipass still not responding after restart"
                return 1
            fi
        fi
    fi

    # Check if multipassd is running
    if ! multipass list >/dev/null 2>&1; then
        log_error "Multipass daemon not responding"
        log_info "Checking service status..."

        if systemctl is-active snap.multipass.multipassd.service >/dev/null 2>&1; then
            log_info "Service is active but not responding"
        else
            log_info "Service is not active. Starting..."
            sudo systemctl start snap.multipass.multipassd.service 2>/dev/null || true
        fi

        # Final check
        if ! multipass list >/dev/null 2>&1; then
            log_error "Unable to connect to multipass service"
            return 1
        fi
    fi

    log_success "Multipass available: $(multipass version 2>&1 | head -1)"
    return 0
}

# Check if Docker is available as fallback
check_docker() {
    if command -v docker >/dev/null 2>&1 || command -v podman >/dev/null 2>&1; then
        log_info "Docker/Podman available as fallback"
        return 0
    fi
    return 1
}

# Create VM with snapshot and validation
create_vm() {
    local vm_version="$1"
    local vm_name="${VM_PREFIX}-${vm_version}"
    local config="${VM_CONFIGS[$vm_version]}"
    IFS=':' read -r image_version _image_name description <<< "$config"

    log_info "Creating VM: $vm_name ($description)"

    # Validate multipass is working before proceeding
    if ! multipass list >/dev/null 2>&1; then
        log_error "Multipass not responding, cannot create VM"
        log_info "Falling back to Docker container creation"
        create_docker_vm "$vm_version"
        return $?
    fi

    # Check if VM already exists
    if multipass list 2>/dev/null | grep -q "^${vm_name}"; then
        log_warning "VM $vm_name already exists"

        # Check VM state
        local vm_state=$(multipass list 2>/dev/null | grep "^${vm_name}" | awk '{print $2}')
        if [[ "$vm_state" == "Stopped" ]]; then
            log_info "Starting stopped VM $vm_name"
            multipass start "$vm_name" 2>/dev/null || log_error "Failed to start VM"
        fi
        return 0
    fi

    # Launch VM with error handling
    log_info "Launching VM with ${DEFAULT_CPUS} CPUs, ${DEFAULT_MEMORY} memory, ${DEFAULT_DISK} disk"

    if timeout 300 multipass launch "$image_version" \
        --name "$vm_name" \
        --cpus "$DEFAULT_CPUS" \
        --memory "$DEFAULT_MEMORY" \
        --disk "$DEFAULT_DISK" 2>&1 | tee /tmp/multipass-launch.log; then

        log_success "VM $vm_name created successfully"

        # Verify VM is running
        if ! multipass list 2>/dev/null | grep "^${vm_name}" | grep -q "Running"; then
            log_error "VM created but not running"
            multipass start "$vm_name" 2>/dev/null || true
        fi

        # Create clean snapshot with validation
        log_info "Creating clean snapshot for $vm_name"
        if multipass snapshot "$vm_name" --name "clean" 2>/dev/null; then
            log_success "Snapshot created successfully"
        else
            log_warning "Snapshot creation failed (may not be supported)"
        fi

        return 0
    else
        log_error "Failed to create VM $vm_name"
        log_info "Error details in /tmp/multipass-launch.log"

        # Try Docker as fallback
        log_info "Attempting Docker fallback..."
        create_docker_vm "$vm_version"
        return $?
    fi
}

# Create VM using Docker as fallback
create_docker_vm() {
    local vm_version="$1"
    local container_name="${VM_PREFIX}-${vm_version}"
    local config="${VM_CONFIGS[$vm_version]}"
    IFS=':' read -r image_version _image_name description <<< "$config"

    log_info "Creating Docker container as VM alternative: $container_name ($description)"

    # Map Ubuntu versions to Docker images
    local docker_image
    case "$vm_version" in
        "2404") docker_image="ubuntu:24.04" ;;
        "2204") docker_image="ubuntu:22.04" ;;
        "2004") docker_image="ubuntu:20.04" ;;
        *) docker_image="ubuntu:latest" ;;
    esac

    # Use podman if available, otherwise docker
    local docker_cmd="docker"
    command -v podman >/dev/null 2>&1 && docker_cmd="podman"

    # Run container with necessary tools
    if $docker_cmd run -d \
        --name "$container_name" \
        --hostname "$container_name" \
        -v "${PROJECT_ROOT}:/workspace:ro" \
        "$docker_image" \
        tail -f /dev/null; then

        # Install basic tools
        $docker_cmd exec "$container_name" bash -c "
            apt-get update && \
            apt-get install -y sudo git curl make bash
        "

        log_success "Docker container $container_name created as VM alternative"
        return 0
    else
        log_error "Failed to create Docker container $container_name"
        return 1
    fi
}

# Deploy and test bootstrap
deploy_and_test() {
    local vm_version="$1"
    local vm_name="${VM_PREFIX}-${vm_version}"
    local test_mode="${2:-full}"

    log_info "Deploying to $vm_name (mode: $test_mode)"

    # Check if using multipass or docker
    if multipass list 2>/dev/null | grep -q "^${vm_name}"; then
        deploy_multipass "$vm_name" "$test_mode"
    else
        deploy_docker "$vm_name" "$test_mode"
    fi
}

# Deploy using multipass
deploy_multipass() {
    local vm_name="$1"
    local test_mode="$2"

    # Restore clean snapshot
    log_info "Restoring clean snapshot for $vm_name"
    multipass restore "${vm_name}.clean" 2>/dev/null || true

    # Transfer project
    log_info "Transferring project to $vm_name"
    multipass transfer -r "${PROJECT_ROOT}" "${vm_name}:machine-rites"

    # Run bootstrap based on mode
    local bootstrap_cmd
    case "$test_mode" in
        "minimal")
            bootstrap_cmd="./bootstrap_machine_rites.sh --unattended --minimal"
            ;;
        "test")
            bootstrap_cmd="./bootstrap_machine_rites.sh --unattended --test"
            ;;
        *)
            bootstrap_cmd="./bootstrap_machine_rites.sh --unattended"
            ;;
    esac

    # Execute bootstrap and capture metrics
    local start_time=$(date +%s)

    if multipass exec "$vm_name" -- bash -c "
        cd machine-rites && \
        $bootstrap_cmd && \
        make validate
    "; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))

        log_success "Bootstrap successful on $vm_name (${duration}s)"

        # Capture metrics
        save_metrics "$vm_name" "success" "$duration" "$test_mode"
        return 0
    else
        log_error "Bootstrap failed on $vm_name"
        save_metrics "$vm_name" "failure" "0" "$test_mode"
        return 1
    fi
}

# Deploy using Docker
deploy_docker() {
    local container_name="$1"
    local test_mode="$2"

    # Determine docker command
    local docker_cmd="docker"
    command -v podman >/dev/null 2>&1 && docker_cmd="podman"

    # Run bootstrap based on mode
    local bootstrap_cmd
    case "$test_mode" in
        "minimal")
            bootstrap_cmd="./bootstrap_machine_rites.sh --unattended --minimal"
            ;;
        "test")
            bootstrap_cmd="./bootstrap_machine_rites.sh --unattended --test"
            ;;
        *)
            bootstrap_cmd="./bootstrap_machine_rites.sh --unattended"
            ;;
    esac

    # Execute bootstrap
    local start_time=$(date +%s)

    if $docker_cmd exec "$container_name" bash -c "
        cd /workspace && \
        $bootstrap_cmd
    "; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))

        log_success "Bootstrap successful on $container_name (${duration}s)"
        save_metrics "$container_name" "success" "$duration" "$test_mode"
        return 0
    else
        log_error "Bootstrap failed on $container_name"
        save_metrics "$container_name" "failure" "0" "$test_mode"
        return 1
    fi
}

# Save deployment metrics
save_metrics() {
    local vm_name="$1"
    local status="$2"
    local duration="$3"
    local mode="$4"
    local metrics_file="${PROJECT_ROOT}/metrics/deployment-stats.json"

    mkdir -p "$(dirname "$metrics_file")"

    # Create metrics entry
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local metrics_entry=$(cat <<EOF
{
  "vm": "$vm_name",
  "status": "$status",
  "duration_seconds": $duration,
  "mode": "$mode",
  "timestamp": "$timestamp"
}
EOF
)

    # Append to metrics file
    if [[ -f "$metrics_file" ]]; then
        echo ",$metrics_entry" >> "$metrics_file"
    else
        echo "[" > "$metrics_file"
        echo "$metrics_entry" >> "$metrics_file"
    fi

    log_info "Metrics saved to $metrics_file"
}

# Run tests on all VMs
test_all() {
    local test_mode="${1:-full}"
    local failed=0

    log_info "Starting test suite on all VMs (mode: $test_mode)"

    for vm_version in "${!VM_CONFIGS[@]}"; do
        if ! deploy_and_test "$vm_version" "$test_mode"; then
            ((failed++))
        fi
    done

    if [[ $failed -eq 0 ]]; then
        log_success "All tests passed!"
        return 0
    else
        log_error "$failed VM(s) failed testing"
        return 1
    fi
}

# Clean up VMs
cleanup_vms() {
    log_info "Cleaning up VMs"

    # Clean multipass VMs
    for vm_version in "${!VM_CONFIGS[@]}"; do
        local vm_name="${VM_PREFIX}-${vm_version}"

        if multipass list 2>/dev/null | grep -q "^${vm_name}"; then
            log_info "Deleting VM $vm_name"
            multipass delete "$vm_name" --purge
        fi
    done

    # Clean Docker containers
    local docker_cmd="docker"
    command -v podman >/dev/null 2>&1 && docker_cmd="podman"

    for vm_version in "${!VM_CONFIGS[@]}"; do
        local container_name="${VM_PREFIX}-${vm_version}"

        if $docker_cmd ps -a 2>/dev/null | grep -q "$container_name"; then
            log_info "Removing container $container_name"
            $docker_cmd rm -f "$container_name"
        fi
    done

    log_success "Cleanup complete"
}

# Generate test report
generate_report() {
    local metrics_file="${PROJECT_ROOT}/metrics/deployment-stats.json"
    local report_file="${PROJECT_ROOT}/metrics/test-report.md"

    if [[ ! -f "$metrics_file" ]]; then
        log_error "No metrics found"
        return 1
    fi

    log_info "Generating test report"

    cat > "$report_file" <<EOF
# Multipass VM Test Report

Generated: $(date)

## Test Summary

EOF

    # Parse metrics and generate summary
    # (This would need jq or similar for proper JSON parsing)

    log_success "Report generated: $report_file"
}

# Show usage
usage() {
    cat <<EOF
Usage: $0 [command] [options]

Commands:
  setup              Create all test VMs with snapshots
  test [mode]        Run tests on all VMs (full|minimal|test)
  deploy <vm> [mode] Deploy and test specific VM
  clean              Remove all test VMs
  report             Generate test report from metrics
  help               Show this help message

VM Versions:
  2204 - Ubuntu 22.04 LTS
  2404 - Ubuntu 24.04 LTS
  2004 - Ubuntu 20.04 LTS

Examples:
  $0 setup                    # Create all test VMs
  $0 test full               # Run full tests on all VMs
  $0 deploy 2204 minimal     # Test minimal install on Ubuntu 22.04
  $0 clean                   # Clean up all VMs
  $0 report                  # Generate test report

EOF
}

# Main function
main() {
    local command="${1:-help}"
    shift || true

    case "$command" in
        setup)
            if check_multipass; then
                for vm_version in "${!VM_CONFIGS[@]}"; do
                    create_vm "$vm_version"
                done
            elif check_docker; then
                log_warning "Multipass not available, using Docker containers"
                for vm_version in "${!VM_CONFIGS[@]}"; do
                    create_docker_vm "$vm_version"
                done
            else
                log_error "Neither Multipass nor Docker available"
                exit 1
            fi
            ;;

        test)
            test_all "${1:-full}"
            ;;

        deploy)
            local vm="${1:-}"
            local mode="${2:-full}"
            if [[ -z "$vm" ]]; then
                log_error "VM version required"
                usage
                exit 1
            fi
            deploy_and_test "$vm" "$mode"
            ;;

        clean|cleanup)
            cleanup_vms
            ;;

        report)
            generate_report
            ;;

        help|--help|-h)
            usage
            ;;

        *)
            log_error "Unknown command: $command"
            usage
            exit 1
            ;;
    esac
}

# Run main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi