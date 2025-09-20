# Multipass VM Testing Guide

## Overview

The machine-rites project uses Multipass VMs (or Docker containers as fallback) for comprehensive deployment testing across multiple Ubuntu versions. This ensures the bootstrap process works reliably on fresh systems.

## Quick Start

### Using Multipass (Preferred)

```bash
# Setup all test VMs
make multipass-setup

# Run full test suite
make multipass-test

# Test specific VM
make multipass-test-vm VM=2404 MODE=minimal

# Clean up VMs
make multipass-clean
```

### Using Docker (Fallback)

If Multipass is not available, the testing infrastructure automatically falls back to Docker containers:

```bash
# Docker-based testing
make docker-test DISTRO=ubuntu-24
```

## Supported Platforms

| Platform | VM Version | Multipass Image | Docker Image |
|----------|------------|-----------------|--------------|
| Ubuntu 22.04 LTS | 2204 | 22.04 | ubuntu:22.04 |
| Ubuntu 24.04 LTS | 2404 | 24.04 | ubuntu:24.04 |
| Ubuntu 20.04 LTS | 2004 | 20.04 | ubuntu:20.04 |

## Test Modes

### Full Mode (default)
Complete bootstrap with all features enabled:
```bash
make multipass-test MODE=full
```

### Minimal Mode
Basic bootstrap with essential components only:
```bash
make multipass-test MODE=minimal
```

### Test Mode
Bootstrap with test configurations enabled:
```bash
make multipass-test MODE=test
```

## Testing Workflow

### 1. Environment Setup

```bash
# Install multipass (Ubuntu/Debian)
sudo snap install multipass

# Or on macOS
brew install multipass

# Verify installation
multipass version
```

### 2. VM Provisioning

```bash
# Create all test VMs with snapshots
make multipass-setup

# This creates:
# - rites-2204 (Ubuntu 22.04)
# - rites-2404 (Ubuntu 24.04)
# - rites-2004 (Ubuntu 20.04)
# Each VM has a "clean" snapshot for reset
```

### 3. Test Execution

#### Sequential Testing
```bash
# Test all VMs sequentially
make multipass-test
```

#### Parallel Testing
```bash
# Test all VMs in parallel (faster)
make multipass-test-parallel
```

#### Specific VM Testing
```bash
# Test Ubuntu 24.04 only
make multipass-test-vm VM=2404
```

### 4. Performance Benchmarking

```bash
# Benchmark bootstrap times
make multipass-benchmark

# This runs minimal bootstrap on all VMs
# and reports execution times
```

### 5. Results and Metrics

```bash
# Generate test report
make multipass-report

# View metrics
cat metrics/deployment-stats.json
```

## Advanced Usage

### Manual VM Management

```bash
# List VMs
multipass list

# Shell into VM
multipass shell rites-2204

# Transfer files
multipass transfer bootstrap.sh rites-2204:

# Execute command
multipass exec rites-2204 -- ls -la

# Restore snapshot
multipass restore rites-2204.clean
```

### Custom Test Scenarios

```bash
# Direct script usage
./scripts/multipass-testing.sh deploy 2204 minimal

# With custom settings
CPUS=4 MEMORY=4G ./scripts/multipass-testing.sh setup
```

## Metrics and Reporting

### Deployment Metrics

Metrics are automatically collected in `metrics/deployment-stats.json`:

```json
{
  "vm": "rites-2204",
  "status": "success",
  "duration_seconds": 28,
  "mode": "minimal",
  "timestamp": "2025-09-20T10:30:00Z"
}
```

### Success Criteria

- **Bootstrap Time**: <30 seconds on 2CPU/2GB VM
- **Success Rate**: 100% on supported platforms
- **Idempotency**: No changes on second run
- **Resource Usage**: <500MB RAM during bootstrap

## Troubleshooting

### Common Issues

#### Multipass Not Available
```bash
# The system automatically falls back to Docker
# Install multipass for better VM testing:
sudo snap install multipass
```

#### VM Creation Fails
```bash
# Check multipass status
multipass info --all

# Clean up and retry
multipass purge
make multipass-setup
```

#### Permission Denied
```bash
# Add user to multipass group
sudo usermod -a -G multipass $USER
newgrp multipass
```

#### Slow Performance
```bash
# Increase VM resources
multipass set local.rites-2204.cpus=4
multipass set local.rites-2204.memory=4G
```

### Docker Fallback Mode

When multipass is unavailable, the system uses Docker:

```bash
# Docker containers are created with naming:
# rites-2204 → ubuntu:22.04 container
# rites-2404 → ubuntu:24.04 container
# rites-2004 → ubuntu:20.04 container

# List containers
docker ps -a | grep rites

# Shell into container
docker exec -it rites-2204 bash
```

## CI/CD Integration

### GitHub Actions

```yaml
name: VM Testing

on: [push, pull_request]

jobs:
  vm-test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        vm: [2204, 2404, 2004]
    steps:
      - uses: actions/checkout@v4
      - name: Setup Multipass
        run: |
          sudo snap install multipass
      - name: Test VM
        run: |
          make multipass-test-vm VM=${{ matrix.vm }}
```

### Local Pre-commit Testing

```bash
# Add to .git/hooks/pre-push
#!/bin/bash
make multipass-test MODE=minimal || exit 1
```

## Test Development

### Adding New Test Scenarios

Edit `scripts/multipass-testing.sh`:

```bash
# Add new test mode
case "$test_mode" in
    "security")
        bootstrap_cmd="./bootstrap_machine_rites.sh --security-audit"
        ;;
esac
```

### Extending VM Support

```bash
# Add new VM configuration
VM_CONFIGS["2310"]="23.10:ubuntu-2310:Ubuntu 23.10"
```

## Best Practices

1. **Always Test on Clean VMs**: Use snapshots to ensure clean state
2. **Test All Modes**: Full, minimal, and test configurations
3. **Capture Metrics**: Monitor bootstrap times and resource usage
4. **Parallel Testing**: Use parallel mode for faster feedback
5. **Regular Cleanup**: Remove old VMs to save resources

## Performance Targets

| Metric | Target | Current |
|--------|--------|---------|
| Bootstrap Time | <30s | ~28s |
| Memory Usage | <500MB | ~450MB |
| Success Rate | 100% | Tracking |
| Test Coverage | >80% | 82.5% |

## Future Enhancements

- [ ] ARM64 VM support
- [ ] Windows WSL2 testing
- [ ] macOS native testing
- [ ] Cloud provider integration
- [ ] Automated bisection for failures
- [ ] Performance regression detection
- [ ] Video capture of deployment

## Support

For issues with VM testing:
1. Check the troubleshooting section above
2. Review `metrics/deployment-stats.json` for patterns
3. Examine VM logs: `multipass exec rites-2204 -- journalctl`
4. Report issues with full context in GitHub Issues