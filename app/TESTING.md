# Testing Guide

This document describes how to run tests for the Baktainer project.

## Quick Start

```bash
# Run all tests
bundle exec rspec

# Run only unit tests
bundle exec rspec spec/unit/

# Run only integration tests  
bundle exec rspec spec/integration/

# Run with coverage
COVERAGE=true bundle exec rspec
```

## CI Testing

For continuous integration, use the provided CI test script:

```bash
./bin/ci-test
```

This script:
- Runs all tests (unit and integration)
- Generates JUnit XML output for CI reporting
- Creates test results in `tmp/rspec_results.xml`

## Test Structure

- **Unit Tests** (`spec/unit/`): Test individual classes and methods in isolation with mocked dependencies
- **Integration Tests** (`spec/integration/`): Test complete workflows using mocked Docker API calls
- **Fixtures** (`spec/fixtures/`): Test data and factory definitions

## Key Features

- **No Docker Required**: All tests use mocked Docker API calls
- **Fast Execution**: Tests complete in ~2 seconds
- **Comprehensive Coverage**: 66 examples testing all major functionality
- **High Test Coverage**: 94.94% line coverage (150/158 lines), 71.11% branch coverage
- **CI Ready**: Automatic test running in GitHub Actions

## GitHub Actions

The CI pipeline automatically:
1. Runs all tests on every push and pull request
2. Prevents Docker image builds if tests fail
3. Uploads test results as artifacts
4. Uses Ruby 3.3 with proper gem caching

## Local Development

Install dependencies:
```bash
bundle install
```

Run tests with coverage:
```bash
COVERAGE=true bundle exec rspec
open coverage/index.html  # View coverage report
```

## Test Coverage Details

Current test coverage metrics:
- **Line Coverage**: 94.94% (150 out of 158 relevant lines)
- **Branch Coverage**: 71.11% (32 out of 45 branches)

Coverage breakdown by file:
- `lib/baktainer.rb`: 94.23% line coverage
- `lib/baktainer/container.rb`: 92.96% line coverage  
- `lib/baktainer/postgres.rb`: 100% line coverage
- `lib/baktainer/mysql.rb`: 100% line coverage
- `lib/baktainer/mariadb.rb`: 100% line coverage
- `lib/baktainer/sqlite.rb`: 100% line coverage
- `lib/baktainer/backup_command.rb`: 100% line coverage
- `lib/baktainer/logger.rb`: 100% line coverage

## Test Dependencies

- RSpec 3.12+ for testing framework
- FactoryBot for test data generation
- WebMock for HTTP request mocking
- SimpleCov for coverage reporting
- RSpec JUnit Formatter for CI reporting