#!/bin/bash

# Performance Monitoring Dashboard
# Real-time performance tracking and metrics collection

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
METRICS_DIR="$PROJECT_ROOT/.claude-flow/metrics"
PERFORMANCE_DIR="$PROJECT_ROOT/.performance"
DASHBOARD_PORT=${PERFORMANCE_DASHBOARD_PORT:-8080}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Initialize monitoring environment
init_monitoring() {
    log "Initializing performance monitoring..."

    mkdir -p "$METRICS_DIR" "$PERFORMANCE_DIR"

    # Create monitoring configuration
    cat > "$PERFORMANCE_DIR/monitor_config.json" <<EOF
{
    "version": "1.0.0",
    "timestamp": "$(date -Iseconds)",
    "collection_interval_seconds": 30,
    "retention_days": 30,
    "metrics": {
        "system": {
            "enabled": true,
            "collect": ["cpu", "memory", "disk", "network"]
        },
        "application": {
            "enabled": true,
            "collect": ["shell_startup", "bootstrap", "git_ops"]
        },
        "docker": {
            "enabled": true,
            "collect": ["image_sizes", "container_stats"]
        },
        "cache": {
            "enabled": true,
            "collect": ["cache_sizes", "cleanup_events"]
        }
    },
    "alerts": {
        "memory_threshold": 85,
        "disk_threshold": 90,
        "cache_threshold": 15
    }
}
EOF

    success "Monitoring configuration created"
}

# Collect system metrics
collect_system_metrics() {
    local timestamp=$(date +%s%3N)

    # Memory metrics
    local mem_total=$(free -m | awk 'NR==2{print $2}')
    local mem_used=$(free -m | awk 'NR==2{print $3}')
    local mem_free=$(free -m | awk 'NR==2{print $4}')
    local mem_usage_percent=$(awk "BEGIN {printf \"%.2f\", ($mem_used / $mem_total) * 100}")

    # CPU metrics
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')

    # Disk metrics
    local disk_usage=$(df -h "$PROJECT_ROOT" | awk 'NR==2{print $5}' | sed 's/%//')
    local disk_free=$(df -h "$PROJECT_ROOT" | awk 'NR==2{print $4}')

    # Create metrics entry
    local metrics_entry="{
        \"timestamp\": $timestamp,
        \"type\": \"system\",
        \"memory\": {
            \"total_mb\": $mem_total,
            \"used_mb\": $mem_used,
            \"free_mb\": $mem_free,
            \"usage_percent\": $mem_usage_percent
        },
        \"cpu\": {
            \"usage_percent\": $cpu_usage,
            \"load_avg\": $load_avg
        },
        \"disk\": {
            \"usage_percent\": $disk_usage,
            \"free\": \"$disk_free\"
        }
    }"

    echo "$metrics_entry" >> "$METRICS_DIR/system-metrics.jsonl"

    # Check alerts
    check_system_alerts "$mem_usage_percent" "$disk_usage"
}

# Collect application metrics
collect_app_metrics() {
    local timestamp=$(date +%s%3N)

    # Shell startup time
    local shell_start=$(date +%s%3N)
    bash -c 'exit 0' 2>/dev/null
    local shell_end=$(date +%s%3N)
    local shell_startup_ms=$((shell_end - shell_start))

    # Git operation time
    local git_start=$(date +%s%3N)
    git -C "$PROJECT_ROOT" status --porcelain >/dev/null 2>&1 || true
    local git_end=$(date +%s%3N)
    local git_time_ms=$((git_end - git_start))

    # Check if bootstrap optimization is available
    local bootstrap_optimized=false
    if [ -f "$PROJECT_ROOT/bootstrap/bootstrap-optimized.sh" ]; then
        bootstrap_optimized=true
    fi

    local metrics_entry="{
        \"timestamp\": $timestamp,
        \"type\": \"application\",
        \"shell_startup_ms\": $shell_startup_ms,
        \"git_status_ms\": $git_time_ms,
        \"bootstrap_optimized\": $bootstrap_optimized
    }"

    echo "$metrics_entry" >> "$METRICS_DIR/app-metrics.jsonl"
}

# Collect Docker metrics
collect_docker_metrics() {
    if ! command -v docker >/dev/null 2>&1; then
        return
    fi

    local timestamp=$(date +%s%3N)

    # Docker image sizes
    local images_data="[]"
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            local repo=$(echo "$line" | awk '{print $1}')
            local tag=$(echo "$line" | awk '{print $2}')
            local size=$(echo "$line" | awk '{print $3}')

            # Convert size to MB
            local size_mb=0
            if [[ $size == *"GB"* ]]; then
                size_mb=$(echo "$size" | sed 's/GB//' | awk '{print $1 * 1024}')
            elif [[ $size == *"MB"* ]]; then
                size_mb=$(echo "$size" | sed 's/MB//' | awk '{print $1}')
            fi

            images_data=$(echo "$images_data" | jq --arg repo "$repo" --arg tag "$tag" --argjson size_mb "$size_mb" \
                '. += [{"repository": $repo, "tag": $tag, "size_mb": $size_mb}]')
        fi
    done < <(docker images --format "{{.Repository}} {{.Tag}} {{.Size}}" 2>/dev/null | grep -E "(oscalize|machine-rites)" || true)

    local metrics_entry="{
        \"timestamp\": $timestamp,
        \"type\": \"docker\",
        \"images\": $images_data
    }"

    echo "$metrics_entry" >> "$METRICS_DIR/docker-metrics.jsonl"
}

# Collect cache metrics
collect_cache_metrics() {
    local timestamp=$(date +%s%3N)

    # Calculate cache sizes
    local cache_dirs=("$HOME/.cache" "$HOME/.npm" "$HOME/.yarn")
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

    local metrics_entry="{
        \"timestamp\": $timestamp,
        \"type\": \"cache\",
        \"total_size_gb\": $total_size_gb,
        \"directories\": $cache_data
    }"

    echo "$metrics_entry" >> "$METRICS_DIR/cache-metrics.jsonl"

    # Check cache alert
    if awk "BEGIN {exit !($total_size_gb > 15)}"; then
        warning "Cache size ${total_size_gb}GB exceeds 15GB threshold"
    fi
}

# Check system alerts
check_system_alerts() {
    local mem_usage=$1
    local disk_usage=$2

    local alerts="[]"

    if awk "BEGIN {exit !($mem_usage > 85)}"; then
        alerts=$(echo "$alerts" | jq '. += [{"type": "memory", "severity": "warning", "value": '$(printf "%.1f" "$mem_usage")', "threshold": 85}]')
        warning "Memory usage ${mem_usage}% exceeds 85% threshold"
    fi

    if [ "$disk_usage" -gt 90 ]; then
        alerts=$(echo "$alerts" | jq '. += [{"type": "disk", "severity": "critical", "value": '$disk_usage', "threshold": 90}]')
        error "Disk usage ${disk_usage}% exceeds 90% threshold"
    fi

    if [ "$alerts" != "[]" ]; then
        local alert_entry="{
            \"timestamp\": $(date +%s%3N),
            \"type\": \"alert\",
            \"alerts\": $alerts
        }"
        echo "$alert_entry" >> "$METRICS_DIR/alerts.jsonl"
    fi
}

# Generate performance dashboard HTML
generate_dashboard() {
    log "Generating performance dashboard..."

    local dashboard_file="$PERFORMANCE_DIR/dashboard.html"

    cat > "$dashboard_file" <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Machine-Rites Performance Dashboard</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            margin: 0;
            padding: 20px;
            background-color: #f5f5f5;
        }
        .container {
            max-width: 1400px;
            margin: 0 auto;
        }
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 20px;
            border-radius: 10px;
            margin-bottom: 20px;
            text-align: center;
        }
        .metrics-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-bottom: 20px;
        }
        .metric-card {
            background: white;
            padding: 20px;
            border-radius: 10px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            border-left: 4px solid #667eea;
        }
        .metric-title {
            font-size: 18px;
            font-weight: 600;
            margin-bottom: 10px;
            color: #333;
        }
        .metric-value {
            font-size: 32px;
            font-weight: 700;
            color: #667eea;
        }
        .metric-unit {
            font-size: 14px;
            color: #666;
            margin-left: 5px;
        }
        .status-good { color: #10b981; }
        .status-warning { color: #f59e0b; }
        .status-critical { color: #ef4444; }
        .charts-container {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(400px, 1fr));
            gap: 20px;
        }
        .chart-card {
            background: white;
            padding: 20px;
            border-radius: 10px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        .chart-title {
            font-size: 16px;
            font-weight: 600;
            margin-bottom: 15px;
            color: #333;
        }
        .last-updated {
            text-align: center;
            color: #666;
            margin-top: 20px;
            font-size: 14px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Machine-Rites Performance Dashboard</h1>
            <p>Real-time performance monitoring and optimization tracking</p>
        </div>

        <div class="metrics-grid">
            <div class="metric-card">
                <div class="metric-title">Shell Startup Time</div>
                <div class="metric-value status-good" id="shell-startup">--<span class="metric-unit">ms</span></div>
                <div>Target: ≤2ms</div>
            </div>

            <div class="metric-card">
                <div class="metric-title">Memory Usage</div>
                <div class="metric-value status-good" id="memory-usage">--<span class="metric-unit">%</span></div>
                <div>Alert: >85%</div>
            </div>

            <div class="metric-card">
                <div class="metric-title">Cache Size</div>
                <div class="metric-value status-good" id="cache-size">--<span class="metric-unit">GB</span></div>
                <div>Target: ≤10GB</div>
            </div>

            <div class="metric-card">
                <div class="metric-title">Docker Images</div>
                <div class="metric-value status-good" id="docker-size">--<span class="metric-unit">MB</span></div>
                <div>Target: ≤500MB</div>
            </div>
        </div>

        <div class="charts-container">
            <div class="chart-card">
                <div class="chart-title">Memory Usage Over Time</div>
                <canvas id="memoryChart"></canvas>
            </div>

            <div class="chart-card">
                <div class="chart-title">Performance Metrics</div>
                <canvas id="performanceChart"></canvas>
            </div>

            <div class="chart-card">
                <div class="chart-title">Cache Growth</div>
                <canvas id="cacheChart"></canvas>
            </div>

            <div class="chart-card">
                <div class="chart-title">System Load</div>
                <canvas id="loadChart"></canvas>
            </div>
        </div>

        <div class="last-updated">
            Last updated: <span id="last-updated">--</span>
        </div>
    </div>

    <script>
        // Dashboard JavaScript will be injected here
        function updateDashboard() {
            // Fetch latest metrics and update charts
            console.log('Updating dashboard...');
            document.getElementById('last-updated').textContent = new Date().toLocaleString();
        }

        // Initialize dashboard
        updateDashboard();
        setInterval(updateDashboard, 30000); // Update every 30 seconds
    </script>
</body>
</html>
EOF

    success "Performance dashboard generated at $dashboard_file"
}

# Start dashboard server
start_dashboard_server() {
    log "Starting performance dashboard server on port $DASHBOARD_PORT..."

    if command -v python3 >/dev/null 2>&1; then
        cd "$PERFORMANCE_DIR"
        python3 -m http.server "$DASHBOARD_PORT" >/dev/null 2>&1 &
        local server_pid=$!
        echo "$server_pid" > "$PERFORMANCE_DIR/dashboard.pid"

        success "Dashboard server started at http://localhost:$DASHBOARD_PORT/dashboard.html"
        log "Server PID: $server_pid"
    else
        warning "Python3 not available, cannot start dashboard server"
    fi
}

# Stop dashboard server
stop_dashboard_server() {
    if [ -f "$PERFORMANCE_DIR/dashboard.pid" ]; then
        local pid=$(cat "$PERFORMANCE_DIR/dashboard.pid")
        kill "$pid" 2>/dev/null || true
        rm -f "$PERFORMANCE_DIR/dashboard.pid"
        success "Dashboard server stopped"
    else
        warning "Dashboard server not running"
    fi
}

# Continuous monitoring mode
monitor_continuous() {
    log "Starting continuous performance monitoring..."

    local interval=${MONITOR_INTERVAL:-30}

    while true; do
        log "Collecting metrics..."

        collect_system_metrics
        collect_app_metrics
        collect_docker_metrics
        collect_cache_metrics

        # Cleanup old metrics (keep 30 days)
        find "$METRICS_DIR" -name "*.jsonl" -mtime +30 -delete 2>/dev/null || true

        log "Metrics collection completed, sleeping ${interval}s..."
        sleep "$interval"
    done
}

# Generate monitoring report
generate_monitoring_report() {
    log "Generating monitoring report..."

    local report_file="$PERFORMANCE_DIR/monitoring_report.json"

    # Analyze recent metrics
    local current_time=$(date +%s%3N)
    local hour_ago=$((current_time - 3600000))

    # Get latest system metrics
    local latest_system="{}"
    if [ -f "$METRICS_DIR/system-metrics.jsonl" ]; then
        latest_system=$(tail -1 "$METRICS_DIR/system-metrics.jsonl" 2>/dev/null || echo "{}")
    fi

    # Get latest app metrics
    local latest_app="{}"
    if [ -f "$METRICS_DIR/app-metrics.jsonl" ]; then
        latest_app=$(tail -1 "$METRICS_DIR/app-metrics.jsonl" 2>/dev/null || echo "{}")
    fi

    # Check for recent alerts
    local recent_alerts="[]"
    if [ -f "$METRICS_DIR/alerts.jsonl" ]; then
        recent_alerts=$(awk -v since="$hour_ago" '{
            if (match($0, /"timestamp": ([0-9]+)/, arr) && arr[1] > since) print $0
        }' "$METRICS_DIR/alerts.jsonl" | jq -s '.' 2>/dev/null || echo "[]")
    fi

    cat > "$report_file" <<EOF
{
    "timestamp": "$(date -Iseconds)",
    "monitoring": {
        "status": "active",
        "collection_interval": 30,
        "retention_days": 30
    },
    "current_metrics": {
        "system": $latest_system,
        "application": $latest_app
    },
    "recent_alerts": $recent_alerts,
    "performance_targets": {
        "shell_startup_ms": 2,
        "bootstrap_time_ms": 1500,
        "docker_size_mb": 500,
        "cache_size_gb": 10
    },
    "dashboard": {
        "url": "http://localhost:$DASHBOARD_PORT/dashboard.html",
        "available": $([ -f "$PERFORMANCE_DIR/dashboard.html" ] && echo "true" || echo "false")
    }
}
EOF

    success "Monitoring report saved to $report_file"

    # Display summary
    local mem_usage=$(echo "$latest_system" | jq -r '.memory.usage_percent // "N/A"')
    local shell_startup=$(echo "$latest_app" | jq -r '.shell_startup_ms // "N/A"')
    local alert_count=$(echo "$recent_alerts" | jq 'length')

    log "Current Status:"
    log "  Memory usage: ${mem_usage}%"
    log "  Shell startup: ${shell_startup}ms"
    log "  Recent alerts: $alert_count"
}

# Main execution
main() {
    case "${1:-monitor}" in
        "init")
            init_monitoring
            ;;
        "collect")
            collect_system_metrics
            collect_app_metrics
            collect_docker_metrics
            collect_cache_metrics
            ;;
        "dashboard")
            generate_dashboard
            start_dashboard_server
            ;;
        "start")
            start_dashboard_server
            ;;
        "stop")
            stop_dashboard_server
            ;;
        "report")
            generate_monitoring_report
            ;;
        "monitor")
            init_monitoring
            generate_dashboard
            monitor_continuous
            ;;
        *)
            error "Unknown command: $1"
            echo "Usage: $0 {init|collect|dashboard|start|stop|report|monitor}"
            exit 1
            ;;
    esac
}

# Handle interrupts gracefully
trap 'stop_dashboard_server; exit 0' INT TERM

# Execute with error handling
if ! main "$@"; then
    error "Performance monitoring operation failed"
    exit 1
fi