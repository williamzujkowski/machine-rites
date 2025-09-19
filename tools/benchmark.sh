#!/bin/bash

# Performance Benchmark Suite for Machine-Rites
# Comprehensive monitoring and optimization validation

set -euo pipefail

# Configuration
BENCHMARK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$BENCHMARK_DIR")"
RESULTS_DIR="$PROJECT_ROOT/.performance"
METRICS_DIR="$PROJECT_ROOT/.claude-flow/metrics"
LOG_FILE="$RESULTS_DIR/benchmark.log"

# Performance targets
TARGET_SHELL_STARTUP_MS=2
TARGET_BOOTSTRAP_TIME_MS=1500
TARGET_DOCKER_SIZE_MB=500
TARGET_CACHE_SIZE_GB=10

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Utility functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "$LOG_FILE"
}

# Setup benchmark environment
setup_benchmark() {
    log "Setting up benchmark environment..."
    mkdir -p "$RESULTS_DIR" "$METRICS_DIR"

    # Create benchmark timestamp
    BENCHMARK_ID="benchmark-$(date +'%Y%m%d-%H%M%S')"
    echo "$BENCHMARK_ID" > "$RESULTS_DIR/current_benchmark.txt"

    log "Benchmark ID: $BENCHMARK_ID"
}

# Benchmark 1: Shell Startup Time
benchmark_shell_startup() {
    log "Benchmarking shell startup time..."

    local total_time=0
    local iterations=10

    for i in $(seq 1 $iterations); do
        local start_time=$(date +%s%3N)
        bash -c 'exit 0' 2>/dev/null
        local end_time=$(date +%s%3N)
        local duration=$((end_time - start_time))
        total_time=$((total_time + duration))
    done

    local avg_time=$((total_time / iterations))

    echo "{
        \"test\": \"shell_startup\",
        \"avg_time_ms\": $avg_time,
        \"target_ms\": $TARGET_SHELL_STARTUP_MS,
        \"passed\": $([ $avg_time -le $TARGET_SHELL_STARTUP_MS ] && echo "true" || echo "false"),
        \"timestamp\": \"$(date -Iseconds)\"
    }" > "$RESULTS_DIR/shell_startup.json"

    if [ $avg_time -le $TARGET_SHELL_STARTUP_MS ]; then
        success "Shell startup: ${avg_time}ms (target: ${TARGET_SHELL_STARTUP_MS}ms) ✓"
    else
        warning "Shell startup: ${avg_time}ms exceeds target of ${TARGET_SHELL_STARTUP_MS}ms"
    fi
}

# Benchmark 2: Bootstrap Performance
benchmark_bootstrap() {
    log "Benchmarking bootstrap performance..."

    if [ ! -f "$PROJECT_ROOT/bootstrap/bootstrap.sh" ]; then
        warning "Bootstrap script not found, skipping benchmark"
        return
    fi

    local start_time=$(date +%s%3N)

    # Run bootstrap in dry-run mode if possible
    if timeout 30s bash "$PROJECT_ROOT/bootstrap/bootstrap.sh" --dry-run 2>/dev/null; then
        local end_time=$(date +%s%3N)
        local duration=$((end_time - start_time))

        echo "{
            \"test\": \"bootstrap_time\",
            \"time_ms\": $duration,
            \"target_ms\": $TARGET_BOOTSTRAP_TIME_MS,
            \"passed\": $([ $duration -le $TARGET_BOOTSTRAP_TIME_MS ] && echo "true" || echo "false"),
            \"timestamp\": \"$(date -Iseconds)\"
        }" > "$RESULTS_DIR/bootstrap.json"

        if [ $duration -le $TARGET_BOOTSTRAP_TIME_MS ]; then
            success "Bootstrap time: ${duration}ms (target: ${TARGET_BOOTSTRAP_TIME_MS}ms) ✓"
        else
            warning "Bootstrap time: ${duration}ms exceeds target of ${TARGET_BOOTSTRAP_TIME_MS}ms"
        fi
    else
        warning "Bootstrap benchmark timed out or failed"
    fi
}

# Benchmark 3: Docker Image Sizes
benchmark_docker_sizes() {
    log "Benchmarking Docker image sizes..."

    if ! command -v docker >/dev/null 2>&1; then
        warning "Docker not available, skipping image size benchmark"
        return
    fi

    local images_data="[]"

    # Check for project-related Docker images
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            local repo=$(echo "$line" | awk '{print $1}')
            local tag=$(echo "$line" | awk '{print $2}')
            local size=$(echo "$line" | awk '{print $3}')

            # Convert size to MB for comparison
            local size_mb=0
            if [[ $size == *"GB"* ]]; then
                size_mb=$(echo "$size" | sed 's/GB//' | awk '{print $1 * 1024}')
            elif [[ $size == *"MB"* ]]; then
                size_mb=$(echo "$size" | sed 's/MB//' | awk '{print $1}')
            fi

            images_data=$(echo "$images_data" | jq --arg repo "$repo" --arg tag "$tag" --arg size "$size" --argjson size_mb "$size_mb" \
                '. += [{"repository": $repo, "tag": $tag, "size": $size, "size_mb": $size_mb}]')
        fi
    done < <(docker images --format "{{.Repository}} {{.Tag}} {{.Size}}" 2>/dev/null | grep -E "(oscalize|machine-rites)" || true)

    echo "{
        \"test\": \"docker_image_sizes\",
        \"images\": $images_data,
        \"target_mb\": $TARGET_DOCKER_SIZE_MB,
        \"timestamp\": \"$(date -Iseconds)\"
    }" > "$RESULTS_DIR/docker_sizes.json"

    # Report on image sizes
    local max_size_mb=0
    while read -r size_mb; do
        if [ "$size_mb" -gt "$max_size_mb" ]; then
            max_size_mb=$size_mb
        fi
    done < <(echo "$images_data" | jq -r '.[].size_mb // 0')

    if [ "$max_size_mb" -le "$TARGET_DOCKER_SIZE_MB" ]; then
        success "Docker images: ${max_size_mb}MB (target: ${TARGET_DOCKER_SIZE_MB}MB) ✓"
    else
        warning "Docker images: ${max_size_mb}MB exceeds target of ${TARGET_DOCKER_SIZE_MB}MB"
    fi
}

# Benchmark 4: Cache Size Analysis
benchmark_cache_usage() {
    log "Benchmarking cache usage..."

    local cache_dirs=(
        "$HOME/.cache"
        "$HOME/.npm"
        "$HOME/.yarn"
        "$PROJECT_ROOT/node_modules"
        "$PROJECT_ROOT/.git"
    )

    local total_size_gb=0
    local cache_data="[]"

    for cache_dir in "${cache_dirs[@]}"; do
        if [ -d "$cache_dir" ]; then
            local size_kb=$(du -sk "$cache_dir" 2>/dev/null | cut -f1 || echo "0")
            local size_gb=$(awk "BEGIN {printf \"%.2f\", $size_kb / 1024 / 1024}")
            total_size_gb=$(awk "BEGIN {printf \"%.2f\", $total_size_gb + $size_gb}")

            cache_data=$(echo "$cache_data" | jq --arg path "$cache_dir" --arg size_gb "$size_gb" \
                '. += [{"path": $path, "size_gb": ($size_gb | tonumber)}]')
        fi
    done

    echo "{
        \"test\": \"cache_usage\",
        \"total_size_gb\": $total_size_gb,
        \"target_gb\": $TARGET_CACHE_SIZE_GB,
        \"directories\": $cache_data,
        \"passed\": $(awk "BEGIN {print ($total_size_gb <= $TARGET_CACHE_SIZE_GB) ? \"true\" : \"false\"}"),
        \"timestamp\": \"$(date -Iseconds)\"
    }" > "$RESULTS_DIR/cache_usage.json"

    if awk "BEGIN {exit !($total_size_gb <= $TARGET_CACHE_SIZE_GB)}"; then
        success "Cache usage: ${total_size_gb}GB (target: ${TARGET_CACHE_SIZE_GB}GB) ✓"
    else
        warning "Cache usage: ${total_size_gb}GB exceeds target of ${TARGET_CACHE_SIZE_GB}GB"
    fi
}

# Benchmark 5: Git Operations Performance
benchmark_git_operations() {
    log "Benchmarking git operations..."

    if [ ! -d "$PROJECT_ROOT/.git" ]; then
        warning "Not in a git repository, skipping git benchmarks"
        return
    fi

    # Test git status performance
    local start_time=$(date +%s%3N)
    git -C "$PROJECT_ROOT" status --porcelain >/dev/null 2>&1
    local end_time=$(date +%s%3N)
    local git_status_time=$((end_time - start_time))

    # Test git log performance
    start_time=$(date +%s%3N)
    git -C "$PROJECT_ROOT" log --oneline -10 >/dev/null 2>&1
    end_time=$(date +%s%3N)
    local git_log_time=$((end_time - start_time))

    # Get repository stats
    local repo_size_mb=$(du -sm "$PROJECT_ROOT/.git" 2>/dev/null | cut -f1 || echo "0")
    local commit_count=$(git -C "$PROJECT_ROOT" rev-list --count HEAD 2>/dev/null || echo "0")

    echo "{
        \"test\": \"git_operations\",
        \"git_status_ms\": $git_status_time,
        \"git_log_ms\": $git_log_time,
        \"repo_size_mb\": $repo_size_mb,
        \"commit_count\": $commit_count,
        \"timestamp\": \"$(date -Iseconds)\"
    }" > "$RESULTS_DIR/git_operations.json"

    success "Git operations: status=${git_status_time}ms, log=${git_log_time}ms"
}

# Benchmark 6: Memory Usage Analysis
benchmark_memory_usage() {
    log "Benchmarking memory usage..."

    # Get current memory stats
    local mem_total=$(free -m | awk 'NR==2{print $2}')
    local mem_used=$(free -m | awk 'NR==2{print $3}')
    local mem_free=$(free -m | awk 'NR==2{print $4}')
    local mem_usage_percent=$(awk "BEGIN {printf \"%.2f\", ($mem_used / $mem_total) * 100}")

    # Get process memory usage
    local top_processes=$(ps aux --sort=-%mem | head -10 | awk 'NR>1{print $11 " " $4}' | jq -R -s 'split("\n")[:-1] | map(split(" ") | {process: .[0], memory_percent: (.[1] | tonumber)})')

    echo "{
        \"test\": \"memory_usage\",
        \"total_mb\": $mem_total,
        \"used_mb\": $mem_used,
        \"free_mb\": $mem_free,
        \"usage_percent\": $mem_usage_percent,
        \"top_processes\": $top_processes,
        \"timestamp\": \"$(date -Iseconds)\"
    }" > "$RESULTS_DIR/memory_usage.json"

    success "Memory usage: ${mem_usage_percent}% (${mem_used}MB/${mem_total}MB)"
}

# Benchmark 7: File I/O Performance
benchmark_file_io() {
    log "Benchmarking file I/O performance..."

    local test_file="$RESULTS_DIR/io_test.tmp"
    local test_size_mb=10

    # Write test
    local start_time=$(date +%s%3N)
    dd if=/dev/zero of="$test_file" bs=1M count=$test_size_mb 2>/dev/null
    sync
    local end_time=$(date +%s%3N)
    local write_time=$((end_time - start_time))
    local write_speed_mb_s=$(awk "BEGIN {printf \"%.2f\", $test_size_mb / ($write_time / 1000)}")

    # Read test
    echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null 2>&1 || true
    start_time=$(date +%s%3N)
    dd if="$test_file" of=/dev/null bs=1M 2>/dev/null
    end_time=$(date +%s%3N)
    local read_time=$((end_time - start_time))
    local read_speed_mb_s=$(awk "BEGIN {printf \"%.2f\", $test_size_mb / ($read_time / 1000)}")

    # Cleanup
    rm -f "$test_file"

    echo "{
        \"test\": \"file_io\",
        \"write_time_ms\": $write_time,
        \"read_time_ms\": $read_time,
        \"write_speed_mb_s\": $write_speed_mb_s,
        \"read_speed_mb_s\": $read_speed_mb_s,
        \"test_size_mb\": $test_size_mb,
        \"timestamp\": \"$(date -Iseconds)\"
    }" > "$RESULTS_DIR/file_io.json"

    success "File I/O: write=${write_speed_mb_s}MB/s, read=${read_speed_mb_s}MB/s"
}

# Generate comprehensive report
generate_report() {
    log "Generating performance report..."

    local report_file="$RESULTS_DIR/performance_report.json"
    local benchmark_id=$(cat "$RESULTS_DIR/current_benchmark.txt" 2>/dev/null || echo "unknown")

    # Collect all benchmark results
    local results="{}"

    for result_file in "$RESULTS_DIR"/*.json; do
        if [ -f "$result_file" ] && [ "$(basename "$result_file")" != "performance_report.json" ]; then
            local test_name=$(basename "$result_file" .json)
            local test_data=$(cat "$result_file")
            results=$(echo "$results" | jq --argjson data "$test_data" --arg name "$test_name" '. += {($name): $data}')
        fi
    done

    # Calculate overall score
    local passed_tests=0
    local total_tests=0

    for test in shell_startup bootstrap docker_sizes cache_usage; do
        if echo "$results" | jq -e ".$test.passed" >/dev/null 2>&1; then
            total_tests=$((total_tests + 1))
            if echo "$results" | jq -e ".$test.passed == true" >/dev/null 2>&1; then
                passed_tests=$((passed_tests + 1))
            fi
        fi
    done

    local score=0
    if [ $total_tests -gt 0 ]; then
        score=$(awk "BEGIN {printf \"%.1f\", ($passed_tests / $total_tests) * 100}")
    fi

    # Generate final report
    cat > "$report_file" <<EOF
{
    "benchmark_id": "$benchmark_id",
    "timestamp": "$(date -Iseconds)",
    "overall_score": $score,
    "passed_tests": $passed_tests,
    "total_tests": $total_tests,
    "results": $results,
    "recommendations": $(generate_recommendations)
}
EOF

    # Display summary
    echo
    log "=== PERFORMANCE BENCHMARK SUMMARY ==="
    log "Benchmark ID: $benchmark_id"
    log "Overall Score: $score% ($passed_tests/$total_tests tests passed)"
    echo

    # Show individual results
    if echo "$results" | jq -e '.shell_startup' >/dev/null 2>&1; then
        local startup_time=$(echo "$results" | jq -r '.shell_startup.avg_time_ms')
        local startup_passed=$(echo "$results" | jq -r '.shell_startup.passed')
        log "Shell Startup: ${startup_time}ms $([ "$startup_passed" = "true" ] && echo "✓" || echo "✗")"
    fi

    if echo "$results" | jq -e '.bootstrap' >/dev/null 2>&1; then
        local bootstrap_time=$(echo "$results" | jq -r '.bootstrap.time_ms // "N/A"')
        local bootstrap_passed=$(echo "$results" | jq -r '.bootstrap.passed // false')
        log "Bootstrap: ${bootstrap_time}ms $([ "$bootstrap_passed" = "true" ] && echo "✓" || echo "✗")"
    fi

    echo
    log "Full report saved to: $report_file"
}

# Generate optimization recommendations
generate_recommendations() {
    local recommendations="[]"

    # Check shell startup
    if [ -f "$RESULTS_DIR/shell_startup.json" ]; then
        local startup_time=$(jq -r '.avg_time_ms' "$RESULTS_DIR/shell_startup.json")
        if [ "$startup_time" -gt "$TARGET_SHELL_STARTUP_MS" ]; then
            recommendations=$(echo "$recommendations" | jq '. += ["Consider optimizing shell initialization scripts and removing unnecessary plugins"]')
        fi
    fi

    # Check bootstrap performance
    if [ -f "$RESULTS_DIR/bootstrap.json" ]; then
        local bootstrap_passed=$(jq -r '.passed' "$RESULTS_DIR/bootstrap.json")
        if [ "$bootstrap_passed" = "false" ]; then
            recommendations=$(echo "$recommendations" | jq '. += ["Implement lazy loading and parallel package checks in bootstrap process"]')
        fi
    fi

    # Check Docker sizes
    if [ -f "$RESULTS_DIR/docker_sizes.json" ]; then
        local max_size=$(jq -r '.images | max_by(.size_mb) | .size_mb // 0' "$RESULTS_DIR/docker_sizes.json")
        if [ "$max_size" -gt "$TARGET_DOCKER_SIZE_MB" ]; then
            recommendations=$(echo "$recommendations" | jq '. += ["Use Alpine base images and multi-stage builds to reduce Docker image sizes"]')
        fi
    fi

    # Check cache usage
    if [ -f "$RESULTS_DIR/cache_usage.json" ]; then
        local cache_passed=$(jq -r '.passed' "$RESULTS_DIR/cache_usage.json")
        if [ "$cache_passed" = "false" ]; then
            recommendations=$(echo "$recommendations" | jq '. += ["Implement cache cleanup policies and consider using cache size limits"]')
        fi
    fi

    echo "$recommendations"
}

# Continuous monitoring mode
monitor_mode() {
    log "Starting continuous performance monitoring..."

    while true; do
        log "Running performance monitoring cycle..."

        # Run lightweight benchmarks
        benchmark_shell_startup
        benchmark_memory_usage

        # Store metrics in Claude Flow format
        if [ -d "$METRICS_DIR" ]; then
            local timestamp=$(date +%s%3N)
            local metrics_entry="{
                \"timestamp\": $timestamp,
                \"shell_startup_ms\": $(jq -r '.avg_time_ms // 0' "$RESULTS_DIR/shell_startup.json" 2>/dev/null),
                \"memory_usage_percent\": $(jq -r '.usage_percent // 0' "$RESULTS_DIR/memory_usage.json" 2>/dev/null),
                \"benchmark_id\": \"monitor-$(date +'%Y%m%d-%H%M%S')\",
                \"monitoring\": true
            }"

            echo "$metrics_entry" >> "$METRICS_DIR/performance-monitoring.jsonl"
        fi

        sleep 300  # 5 minute intervals
    done
}

# Main execution
main() {
    case "${1:-full}" in
        "shell")
            setup_benchmark
            benchmark_shell_startup
            ;;
        "bootstrap")
            setup_benchmark
            benchmark_bootstrap
            ;;
        "docker")
            setup_benchmark
            benchmark_docker_sizes
            ;;
        "cache")
            setup_benchmark
            benchmark_cache_usage
            ;;
        "git")
            setup_benchmark
            benchmark_git_operations
            ;;
        "memory")
            setup_benchmark
            benchmark_memory_usage
            ;;
        "io")
            setup_benchmark
            benchmark_file_io
            ;;
        "monitor")
            setup_benchmark
            monitor_mode
            ;;
        "full"|*)
            setup_benchmark
            benchmark_shell_startup
            benchmark_bootstrap
            benchmark_docker_sizes
            benchmark_cache_usage
            benchmark_git_operations
            benchmark_memory_usage
            benchmark_file_io
            generate_report
            ;;
    esac
}

# Run with error handling
if ! main "$@"; then
    error "Benchmark execution failed"
    exit 1
fi