# Docker Testing Infrastructure

This directory contains the Docker testing infrastructure for the machine-rites project, implementing Phase 1.1 of the project plan.

## Overview

The Docker infrastructure provides multi-distribution testing capabilities with:
- **Ubuntu 24.04** - Latest LTS for bleeding-edge testing
- **Ubuntu 22.04** - Previous LTS for compatibility testing
- **Debian 12** - Stable baseline for maximum compatibility

## Architecture

```
docker/
├── ubuntu-24.04/Dockerfile    # Ubuntu 24.04 test environment
├── ubuntu-22.04/Dockerfile    # Ubuntu 22.04 test environment
├── debian-12/Dockerfile       # Debian 12 test environment
├── test-harness.sh           # Comprehensive test runner
├── validate-environment.sh   # Environment validation
└── .dockerignore            # Build context optimization
```

## Features

### Multi-Distribution Testing
- **Parallel Execution**: Run tests across all distros simultaneously
- **Isolation**: Each distro runs in its own container with dedicated volumes
- **Live Development**: Real-time file mounting for active development

### Test User Setup
- **Dedicated Test User**: `testuser` with sudo access (password: `testpass`)
- **Proper Permissions**: Pre-configured for development tools installation
- **Clean Environment**: Fresh environment for each test run

### Volume Mounts
- **Source Code**: Live mounting of entire repository
- **Test Artifacts**: Dedicated volumes for test results and logs
- **Temporary Files**: Isolated temp directories per distro

### Health Checks
- **Container Health**: Built-in health monitoring for all containers
- **Service Validation**: Automated checks for required tools and permissions
- **Resource Monitoring**: Memory, disk, and CPU usage validation

## Quick Start

### 1. Validate Environment
```bash
make docker-validate
# or
./docker/validate-environment.sh
```

### 2. Build Images
```bash
# Build all distros
make docker-build DISTRO=all

# Build specific distro
make docker-build DISTRO=ubuntu-24
```

### 3. Run Tests
```bash
# Test all distros in parallel
make docker-test-parallel TEST=bootstrap

# Test specific distro
make docker-test DISTRO=debian-12 TEST=integration

# Full test suite
make docker-test-all
```

### 4. Interactive Development
```bash
# Open shell in Ubuntu 24.04
make docker-shell DISTRO=ubuntu-24

# Or use test harness directly
./docker/test-harness.sh shell ubuntu-24
```

## Test Harness Usage

The `test-harness.sh` script provides comprehensive testing capabilities:

```bash
# Basic usage
./docker/test-harness.sh [OPTIONS] COMMAND [ARGS]

# Available commands
build [DISTRO]           # Build images
test [DISTRO] [TEST]     # Run tests
shell [DISTRO]           # Interactive shell
validate [DISTRO]        # Environment validation
clean                    # Cleanup resources
status                   # Container status
logs [DISTRO]            # View logs
health                   # Health checks
all                      # Full test suite

# Options
--parallel               # Parallel execution
--force                  # Force operations
--no-cache              # Build without cache
--verbose               # Detailed output
```

## Makefile Integration

The Docker infrastructure integrates with the project Makefile:

### Docker Operations
- `make docker-build` - Build test images
- `make docker-test` - Run tests
- `make docker-shell` - Interactive shell
- `make docker-clean` - Cleanup resources

### Validation
- `make docker-validate` - Environment validation
- `make validate-structure` - Project structure check
- `make deps-check` - Dependency verification

### Development
- `make setup` - Complete environment setup
- `make dev-shell` - Development shell
- `make lint` - Code linting

## Configuration

### Environment Variables
- `DISTRO` - Target distribution (ubuntu-24, ubuntu-22, debian-12, all)
- `TEST` - Test type (unit, integration, bootstrap, all)
- `DOCKER_BUILDKIT` - Enable BuildKit for faster builds

### Docker Compose
The `docker-compose.test.yml` file provides:
- **Service Definitions**: One service per supported distro
- **Volume Mappings**: Optimized for development and testing
- **Network Isolation**: Dedicated test network
- **Health Checks**: Automated container health monitoring

## Troubleshooting

### Common Issues

#### Permission Denied
```bash
# Add user to docker group
sudo usermod -aG docker $USER
# Re-login or restart shell
```

#### Build Failures
```bash
# Clear Docker cache
make docker-clean-all
# Rebuild without cache
make docker-build-nocache DISTRO=all
```

#### Container Health Issues
```bash
# Check container status
make docker-health
# View logs
make docker-logs DISTRO=ubuntu-24
```

#### Network Issues
```bash
# Validate network connectivity
./docker/validate-environment.sh --no-network
# Reset Docker networks
docker network prune -f
```

### Performance Tips

#### Faster Builds
```bash
# Enable BuildKit
export DOCKER_BUILDKIT=1
# Use parallel builds
make docker-build DISTRO=all
```

#### Resource Optimization
```bash
# Limit parallel containers
COMPOSE_PARALLEL_LIMIT=2 make docker-test-parallel
# Monitor resource usage
docker stats
```

## Best Practices

### Development Workflow
1. **Validate First**: Always run `make docker-validate` before starting
2. **Build Once**: Build all images at the start of your session
3. **Test Incrementally**: Use specific distros for focused testing
4. **Clean Regularly**: Run `make docker-clean` to free resources

### Testing Strategy
1. **Start Small**: Test individual modules before full bootstrap
2. **Use Parallel**: Leverage parallel testing for faster feedback
3. **Monitor Health**: Check container health regularly
4. **Save Logs**: Capture logs for debugging and analysis

### Resource Management
1. **Clean Up**: Always clean up after testing sessions
2. **Monitor Usage**: Keep an eye on disk space and memory
3. **Prune Regularly**: Use `docker system prune` for cleanup
4. **Limit Parallelism**: Adjust based on system capabilities

## Integration with SPARC

This Docker infrastructure supports the SPARC (Specification, Pseudocode, Architecture, Refinement, Completion) methodology:

- **Specification**: Validate requirements across multiple distributions
- **Pseudocode**: Test algorithm implementations in isolated environments
- **Architecture**: Verify system design across different OS variants
- **Refinement**: Iterative testing with rapid feedback loops
- **Completion**: Final validation before deployment

## Security Considerations

### Container Security
- **Non-root User**: All operations run as `testuser`, not root
- **Limited Privileges**: Sudo access only for specific operations
- **Isolated Networks**: Containers run in dedicated test network
- **Volume Restrictions**: Limited host filesystem access

### Image Security
- **Base Images**: Use official Ubuntu/Debian images only
- **Package Updates**: Regular security updates during builds
- **Minimal Surface**: Install only required packages
- **Health Monitoring**: Continuous health validation

## Future Enhancements

### Planned Features
- **Cross-Platform**: Windows and macOS support via Docker Desktop
- **Cloud Integration**: Support for cloud-based testing environments
- **Performance Metrics**: Detailed performance benchmarking
- **Security Scanning**: Automated vulnerability scanning

### Integration Opportunities
- **CI/CD**: GitHub Actions integration for automated testing
- **Monitoring**: Prometheus/Grafana for container monitoring
- **Orchestration**: Kubernetes support for scalable testing
- **Caching**: Advanced build caching strategies

---

**Note**: This infrastructure follows DRY and SOLID principles, ensuring maintainable and extensible testing capabilities for the machine-rites project.