# Docker Testing Infrastructure Usage Guide

## Quick Start

### 1. Validate Your Environment
```bash
# Check Docker and dependencies
./docker/validate-environment.sh

# Quick validation (skip network tests)
./docker/validate-environment.sh --quick
```

### 2. Build Test Images
```bash
# Build all distributions
./docker/test-harness.sh build all

# Build specific distro
./docker/test-harness.sh build ubuntu-24
```

### 3. Run Tests
```bash
# Run bootstrap test on Ubuntu 24.04
./docker/test-harness.sh test ubuntu-24 bootstrap

# Run all tests in parallel
./docker/test-harness.sh --parallel test all all

# Run complete test suite
./docker/test-harness.sh all
```

### 4. Interactive Development
```bash
# Open shell in Ubuntu 24.04 container
./docker/test-harness.sh shell ubuntu-24

# Inside container, you'll have:
# - Full machine-rites codebase mounted at /opt/machine-rites
# - testuser with sudo access
# - All development tools pre-installed
```

## Advanced Usage

### Parallel Testing
```bash
# Test bootstrap across all distros simultaneously
./docker/test-harness.sh --parallel test all bootstrap

# Test different scenarios in parallel
./docker/test-harness.sh --parallel test all integration
```

### Build Optimization
```bash
# Build without cache (for clean builds)
./docker/test-harness.sh build all --no-cache

# Force rebuild
./docker/test-harness.sh --force build all
```

### Monitoring and Debugging
```bash
# Check container health
./docker/test-harness.sh health

# View container status
./docker/test-harness.sh status

# View logs from specific distro
./docker/test-harness.sh logs ubuntu-24

# View all logs
./docker/test-harness.sh logs all
```

### Cleanup
```bash
# Standard cleanup
./docker/test-harness.sh clean

# Force cleanup (removes images too)
./docker/test-harness.sh --force clean
```

## Integration with Makefile

If your project has a Makefile, you can include Docker targets:

```makefile
# Add to your Makefile
include docker/docker-targets.mk

# Then use:
make docker-build DISTRO=ubuntu-24
make docker-test DISTRO=all TEST=bootstrap
make docker-shell DISTRO=debian-12
```

## Container Details

### Test User
- **Username**: `testuser`
- **Password**: `testpass`
- **Privileges**: Full sudo access (passwordless)
- **Home**: `/home/testuser`
- **Workspace**: `/opt/machine-rites`

### Installed Tools
- **Shell**: bash, zsh available
- **Version Control**: git
- **Build Tools**: make, gcc, build-essential
- **Scripting**: python3, nodejs, npm
- **Quality**: shellcheck, bats (testing framework)
- **Utilities**: curl, wget, jq, tree, vim, nano

### Volume Mounts
- **Source Code**: `.` → `/opt/machine-rites` (read-write)
- **Test Results**: `test-artifacts-{distro}` → `/tmp/test-artifacts`
- **Temporary**: `/tmp/machine-rites-{distro}` → `/tmp/machine-rites`

## Environment Variables

### Inside Containers
- `MACHINE_RITES_TEST=true` - Indicates test environment
- `DISTRO={distro}` - Current distribution identifier
- `TEST_RUNNER=docker` - Indicates Docker-based testing
- `CI=true` - Enables CI-friendly output

### Configuration
- `DOCKER_BUILDKIT=1` - Enable BuildKit for faster builds
- `COMPOSE_PARALLEL_LIMIT=3` - Limit parallel operations

## Troubleshooting

### Permission Issues
```bash
# Ensure user is in docker group
sudo usermod -aG docker $USER
# Then logout and login again
```

### Build Failures
```bash
# Clear Docker cache
./docker/test-harness.sh --force clean
# Rebuild from scratch
./docker/test-harness.sh build all --no-cache
```

### Container Won't Start
```bash
# Check Docker daemon
sudo systemctl status docker
# Restart if needed
sudo systemctl restart docker
```

### Network Issues
```bash
# Validate without network tests
./docker/validate-environment.sh --no-network
# Reset Docker networks
docker network prune -f
```

### Resource Issues
```bash
# Check system resources
docker system df
# Clean up unused resources
docker system prune -f
```

## Best Practices

### Development Workflow
1. Start with `./docker/validate-environment.sh`
2. Build images once per session: `./docker/test-harness.sh build all`
3. Use specific distros for focused testing
4. Use parallel testing for broader validation
5. Clean up regularly: `./docker/test-harness.sh clean`

### Testing Strategy
- **Unit Tests**: `./docker/test-harness.sh test ubuntu-24 unit`
- **Integration**: `./docker/test-harness.sh test debian-12 integration`
- **Bootstrap**: `./docker/test-harness.sh test all bootstrap`
- **Full Suite**: `./docker/test-harness.sh all`

### Performance Tips
- Use `DOCKER_BUILDKIT=1` for faster builds
- Build all images at session start
- Use `--parallel` for multi-distro testing
- Monitor resources with `docker stats`
- Clean up regularly to free disk space

## Examples

### Complete Development Session
```bash
# 1. Validate environment
./docker/validate-environment.sh

# 2. Build all test images
./docker/test-harness.sh build all

# 3. Run quick validation
./docker/test-harness.sh validate all

# 4. Test specific feature
./docker/test-harness.sh test ubuntu-24 bootstrap

# 5. Debug in interactive shell
./docker/test-harness.sh shell ubuntu-24

# 6. Run full test suite
./docker/test-harness.sh all

# 7. Clean up
./docker/test-harness.sh clean
```

### CI/CD Pipeline Usage
```bash
# Validate environment (no network tests in CI)
./docker/validate-environment.sh --quick --no-network

# Build images
./docker/test-harness.sh build all --no-cache

# Run parallel tests
./docker/test-harness.sh --parallel test all all

# Collect results (logs saved automatically)
./docker/test-harness.sh logs all > test-results.log
```

### Debugging Session
```bash
# Build specific image for debugging
./docker/test-harness.sh build ubuntu-24 --no-cache

# Start container with shell
./docker/test-harness.sh shell ubuntu-24

# Inside container:
cd /opt/machine-rites
./bootstrap/bootstrap_machine_rites.sh --dry-run
# ... debug as needed ...

# View logs from host
./docker/test-harness.sh logs ubuntu-24
```

## Integration Points

### GitHub Actions
```yaml
- name: Validate Docker Environment
  run: ./docker/validate-environment.sh --quick

- name: Build Test Images
  run: ./docker/test-harness.sh build all

- name: Run Tests
  run: ./docker/test-harness.sh --parallel test all all
```

### Local Development
```bash
# Add to your .bashrc or .zshrc
alias dr-build='./docker/test-harness.sh build all'
alias dr-test='./docker/test-harness.sh test'
alias dr-shell='./docker/test-harness.sh shell'
alias dr-clean='./docker/test-harness.sh clean'
```

This infrastructure provides a robust, scalable foundation for testing machine-rites across multiple distributions with comprehensive validation and development support.