# Docker CI Infrastructure

This directory contains the Docker-based CI infrastructure for testing machine-rites across multiple distributions and scenarios.

## Files

- `docker-ci.yml` - Main GitHub Actions workflow
- `Dockerfile.*` - Docker images for each distribution
- `test-runner.sh` - Test execution script
- `docker-compose.test.yml` - Local testing compose file
- `local-test.sh` - Local testing script

## Supported Environments

### Distributions
- Ubuntu 24.04 LTS
- Ubuntu 22.04 LTS
- Debian 12 (Bookworm)

### Test Scenarios
- **Fresh**: Clean installation from scratch
- **Upgrade**: Install minimal version then upgrade
- **Minimal**: Minimal installation only

## Usage

### GitHub Actions
The workflow runs automatically on:
- Push to `main`, `master`, `develop` branches
- Pull requests to `main`, `master`
- Manual workflow dispatch

### Local Testing

```bash
# Run all tests
.github/docker/local-test.sh

# Run specific scenario
.github/docker/local-test.sh --scenario fresh

# Run on specific distro
.github/docker/local-test.sh --distro ubuntu-24.04

# Run in parallel with cleanup
.github/docker/local-test.sh --clean --parallel

# Run all scenarios on all distros
.github/docker/local-test.sh --scenario all --distro all
```

### Docker Compose

```bash
# Run basic tests
docker-compose -f .github/docker/docker-compose.test.yml up --build

# Run upgrade tests
docker-compose -f .github/docker/docker-compose.test.yml --profile upgrade up --build

# Run minimal tests
docker-compose -f .github/docker/docker-compose.test.yml --profile minimal up --build
```

## CI Features

### Parallel Execution
- Matrix builds for all distro/scenario combinations
- Docker layer caching for faster builds
- Parallel test execution

### Test Results
- Aggregated test results across all combinations
- Test artifacts with detailed logs
- PR comments with results summary
- Dashboard with success rates

### Caching Strategy
- Docker buildx cache for layer optimization
- Cache keys based on file content hashes
- Separate caches per distribution

### Failure Handling
- Continue-on-error for matrix jobs
- Detailed failure notifications
- Security scanning with Trivy
- Comprehensive logging

## Test Result Structure

```
test-results/
├── {distro}-{scenario}/
│   ├── result.txt          # Test outcome
│   ├── test.log           # Detailed execution log
│   ├── ci-test.log        # CI test output
│   ├── lint.log           # Linting output
│   └── system-info.txt    # System information
```

## Environment Variables

- `TEST_SCENARIO` - Test scenario (fresh, upgrade, minimal)
- `CI` - Set to `true` in CI environment
- `TIMEOUT_DURATION` - Test timeout in seconds (default: 300)
- `TEST_RESULTS_DIR` - Results directory (default: /test-results)
- `WORKSPACE_DIR` - Workspace directory (default: /workspace)

## Troubleshooting

### Local Testing Issues

1. **Docker not running**: Ensure Docker daemon is started
2. **Permission errors**: Check Docker group membership
3. **Build failures**: Clean images with `--clean` option
4. **Timeout errors**: Increase `TIMEOUT_DURATION`

### CI Issues

1. **Cache misses**: Check file hash changes in cache keys
2. **Test failures**: Review artifacts and logs
3. **Resource limits**: Consider reducing parallel jobs

## Security

- Non-root user execution in containers
- Minimal base images
- Trivy vulnerability scanning
- No secrets in logs or artifacts