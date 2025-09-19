# machine-rites Testing Framework

Comprehensive test suite for the machine-rites dotfiles management system, implementing a Test Pyramid approach with Unit, Integration, and End-to-End testing.

## Overview

This testing framework provides:

- **Unit Tests**: Fast, isolated tests for individual functions and components
- **Integration Tests**: Tests for component interactions and workflows
- **End-to-End Tests**: Complete system tests simulating real-world usage
- **Performance Benchmarks**: Performance and resource usage validation
- **Coverage Analysis**: Code coverage reporting with multiple output formats
- **Mutation Testing**: Robustness validation through code mutations
- **Parallel Execution**: Concurrent test execution for faster feedback

## Quick Start

```bash
# Run all tests
./run_tests.sh

# Run specific test categories
./run_tests.sh -t unit
./run_tests.sh -t integration,e2e

# Run with coverage and parallel execution
./run_tests.sh -c -p

# Generate coverage report
./coverage_report.sh
```

## Directory Structure

```
tests/
├── unit/                   # Unit tests
│   ├── test_atomic_operations.sh
│   ├── test_validation.sh
│   ├── test_platform_detection.sh
│   └── test_bootstrap.sh
├── integration/            # Integration tests
│   ├── test_chezmoi_apply.sh
│   └── test_rollback.sh
├── e2e/                   # End-to-end tests
│   └── test_complete_bootstrap.sh
├── fixtures/              # Test data and mock objects
│   └── test_data.sh
├── reports/               # Generated test reports
├── coverage/              # Coverage analysis data
├── benchmarks/            # Performance benchmark results
├── mocks/                 # Mock environments
├── test-framework.sh      # Core testing framework
├── run_tests.sh          # Test runner
├── coverage_report.sh    # Coverage analysis
└── README.md             # This file
```

## Test Framework Features

### Core Testing Functions

```bash
# Assertion functions
assert_equals "expected" "actual" "message"
assert_not_equals "expected" "actual" "message"
assert_contains "haystack" "needle" "message"
assert_file_exists "/path/to/file" "message"
assert_command_succeeds "command" "message"
assert_command_fails "command" "message"
assert_regex_match "string" "pattern" "message"

# Test execution
run_test "test_name" test_function
skip_test "test_name" "reason"

# Test suite management
start_test_suite "suite_name"
end_test_suite

# Mock environment
mock_env=$(setup_mock_environment "test_name")
cleanup_mock_environment "$mock_env"
```

### Performance Benchmarking

```bash
# Benchmark function performance
benchmark_function "function_name" iterations

# Example
benchmark_function "parse_config_file" 100
```

### Coverage Analysis

```bash
# Enable coverage for tests
export COVERAGE_ENABLED=true

# Analyze specific script
analyze_coverage "/path/to/script.sh"
```

## Running Tests

### Basic Usage

```bash
# Run all tests with default settings
./run_tests.sh

# Run with verbose output
./run_tests.sh -v

# Run in parallel
./run_tests.sh -p

# Run specific test types
./run_tests.sh -t unit,integration
```

### Advanced Options

```bash
# Run with coverage analysis
./run_tests.sh -c

# Run with mutation testing
./run_tests.sh -m

# Run performance benchmarks
./run_tests.sh -b

# Filter tests by pattern
./run_tests.sh -f "*atomic*"

# Exclude tests by pattern
./run_tests.sh -x "*slow*"

# Dry run (show execution plan)
./run_tests.sh --dry-run
```

## Test Categories

### Unit Tests (`tests/unit/`)

Fast, isolated tests for individual functions:

- **test_atomic_operations.sh**: Tests core atomic operations and helper functions
- **test_validation.sh**: Tests input validation and sanitization
- **test_platform_detection.sh**: Tests platform-specific detection logic
- **test_bootstrap.sh**: Tests bootstrap script core functionality

### Integration Tests (`tests/integration/`)

Tests for component interactions:

- **test_chezmoi_apply.sh**: Tests complete chezmoi workflow
- **test_rollback.sh**: Tests backup and rollback functionality

### End-to-End Tests (`tests/e2e/`)

Complete system tests:

- **test_complete_bootstrap.sh**: Tests entire bootstrap process from start to finish

## Coverage Reporting

### Generate Coverage Reports

```bash
# Generate HTML coverage report
./coverage_report.sh

# Generate text report with 90% threshold
./coverage_report.sh -t 90 -f text

# Generate JSON report excluding test files
./coverage_report.sh -f json -x "*test*"
```

### Coverage Formats

- **HTML**: Interactive web-based report with visual coverage indicators
- **Text**: Plain text summary suitable for console output
- **JSON**: Machine-readable format for CI/CD integration

### Coverage Metrics

- **Line Coverage**: Percentage of executable lines covered by tests
- **Function Coverage**: Percentage of functions tested
- **Branch Coverage**: Percentage of conditional branches tested

## Mock Environments

The testing framework provides isolated mock environments:

```bash
# Create mock environment
mock_env=$(setup_mock_environment "test_name")

# Environment includes:
# - Isolated HOME directory
# - Mock system commands (apt, git, chezmoi, etc.)
# - Test configuration files
# - Temporary file system

# Cleanup after tests
cleanup_mock_environment "$mock_env"
```

## Performance Benchmarking

### Benchmark Individual Functions

```bash
# Benchmark with default iterations (100)
benchmark_function "my_function"

# Benchmark with custom iterations
benchmark_function "my_function" 500

# Results stored in tests/reports/benchmarks.csv
```

### System Performance Tests

- Bootstrap execution time validation
- Memory usage monitoring
- Disk space usage tracking
- CPU utilization measurement

## Mutation Testing

Mutation testing validates test robustness by introducing code mutations:

```bash
# Run mutation tests
./run_tests.sh -m

# Mutations include:
# - Operator changes (== to !=, && to ||)
# - Boundary modifications (> to >=, < to <=)
# - Conditional logic alterations

# Results in tests/reports/mutations.csv
```

## CI/CD Integration

### JUnit XML Output

Tests automatically generate JUnit XML reports for CI/CD integration:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="Unit_Tests" timestamp="2024-01-01T00:00:00">
    <testcase name="test_atomic_operations" classname="Unit_Tests" time="0.123"/>
    <testcase name="test_validation" classname="Unit_Tests" time="0.098"/>
  </testsuite>
</testsuites>
```

### Exit Codes

- `0`: All tests passed
- `1`: One or more tests failed
- `2`: Test execution error

### Environment Variables

```bash
# Test framework configuration
export VERBOSE_OUTPUT=true          # Enable verbose logging
export COVERAGE_ENABLED=true        # Enable coverage analysis
export PARALLEL_EXECUTION=true      # Enable parallel test execution

# Test data configuration
export TEST_USER_EMAIL="test@example.com"
export TEST_USER_NAME="Test User"
export TEST_HOSTNAME="test-machine"
```

## Test Data and Fixtures

The `tests/fixtures/test_data.sh` provides:

### Sample Configurations

```bash
# Create sample configuration files
create_sample_bashrc "/path/to/.bashrc"
create_sample_gitconfig "/path/to/.gitconfig"
create_sample_chezmoi_config "/path/to/chezmoi.toml"
```

### Mock System Information

```bash
# Get mock system info
mock_system_info | jq '.os'  # "linux"
```

### Test Environment Creation

```bash
# Create test environments
create_test_environment "/tmp/test_env" "basic"    # Basic environment
create_test_environment "/tmp/test_env" "complex"  # Complex with multiple configs
create_test_environment "/tmp/test_env" "minimal"  # Minimal setup
```

## Best Practices

### Writing Tests

1. **Test Structure**: Use Arrange-Act-Assert pattern
2. **Descriptive Names**: Test names should explain what and why
3. **Single Responsibility**: Each test should verify one behavior
4. **Independent Tests**: Tests should not depend on each other
5. **Mock External Dependencies**: Use mocks for external systems

### Test Organization

1. **Logical Grouping**: Group related tests in the same file
2. **Clear Categories**: Separate unit, integration, and e2e tests
3. **Shared Fixtures**: Use common test data for consistency
4. **Cleanup**: Always clean up test artifacts

### Performance Considerations

1. **Fast Unit Tests**: Unit tests should complete in <100ms
2. **Parallel Execution**: Use parallel execution for faster feedback
3. **Resource Management**: Monitor memory and disk usage
4. **Optimization**: Benchmark critical paths regularly

## Troubleshooting

### Common Issues

1. **Permission Errors**: Ensure test scripts are executable
2. **Path Issues**: Use absolute paths in test environments
3. **Mock Failures**: Verify mock commands are in PATH
4. **Coverage Issues**: Check that scripts are syntactically valid

### Debug Mode

```bash
# Enable debug output
export DEBUG=1
./run_tests.sh -v

# Check test framework
bash -x tests/test-framework.sh
```

### Logs and Reports

- Test execution logs: `tests/reports/test-results-*.xml`
- Coverage reports: `tests/coverage/coverage-report-*.html`
- Benchmark results: `tests/reports/benchmarks.csv`
- Mutation testing: `tests/reports/mutations.csv`

## Contributing

When adding new tests:

1. Follow the existing test structure and naming conventions
2. Include appropriate assertions and error handling
3. Add mock environments for isolation
4. Update this README if adding new features
5. Ensure tests pass in both sequential and parallel modes

### Test Template

```bash
#!/usr/bin/env bash
# Unit Tests - [Description]
# Tests [what is being tested]
set -euo pipefail

# Source test framework
source "$(dirname "${BASH_SOURCE[0]}")/../test-framework.sh"

# Test configuration
readonly SCRIPT_UNDER_TEST="$PROJECT_ROOT/script.sh"
readonly MOCK_ENV="$(setup_mock_environment "test_name")"

# Test setup
setup_tests() {
    export HOME="$MOCK_ENV/home"
    mkdir -p "$HOME"
    log_debug "Setup test environment in: $MOCK_ENV"
}

# Test teardown
cleanup_tests() {
    cleanup_mock_environment "$MOCK_ENV"
}

# Test functions
test_example_functionality() {
    # Arrange
    local input="test_input"
    local expected="expected_output"

    # Act
    local actual
    actual=$(process_input "$input")

    # Assert
    assert_equals "$expected" "$actual" "function should process input correctly"
}

# Test execution
main() {
    init_test_framework
    start_test_suite "Example_Tests"

    setup_tests

    run_test "Example Functionality" test_example_functionality

    cleanup_tests
    end_test_suite
    finalize_test_framework
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
```

## License

This testing framework is part of the machine-rites project and follows the same license terms.