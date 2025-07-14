# Baktainer Testing Guide

This directory contains the complete test suite for Baktainer, including unit tests, integration tests, and testing infrastructure.

## Test Structure

```
spec/
├── unit/                   # Unit tests for individual components
│   ├── backup_command_spec.rb   # Tests for backup command generation
│   ├── container_spec.rb        # Tests for container management
│   └── baktainer_spec.rb        # Tests for main runner class
├── integration/           # Integration tests with real containers
│   └── backup_workflow_spec.rb  # End-to-end backup workflow tests
├── fixtures/             # Test data and configuration
│   ├── docker-compose.test.yml  # Test database containers
│   └── factories.rb             # Test data factories
├── support/              # Test support files
│   └── coverage.rb              # Coverage configuration
├── spec_helper.rb        # Main test configuration
└── README.md            # This file
```

## Running Tests

### Quick Start

```bash
# Run unit tests only (fast)
cd app && bundle exec rspec spec/unit/

# Run all tests with coverage
cd app && COVERAGE=true bundle exec rspec

# Use the test runner script
cd app && bin/test --all --coverage
```

### Test Runner Script

The `bin/test` script provides a convenient way to run tests with various options:

```bash
# Run unit tests (default)
bin/test

# Run integration tests with container setup
bin/test --integration --setup --cleanup

# Run all tests with coverage
bin/test --all --coverage

# Show help
bin/test --help
```

### Using Rake Tasks

```bash
# Install dependencies
rake install

# Run unit tests
rake spec

# Run integration tests
rake integration

# Run all tests
rake spec_all

# Run tests with coverage
rake coverage

# Full test suite with setup/cleanup
rake test_full

# Open coverage report
rake coverage_report
```

## Test Categories

### Unit Tests

Unit tests focus on individual components in isolation:

- **Backup Command Tests** (`backup_command_spec.rb`): Test command generation for different database engines
- **Container Tests** (`container_spec.rb`): Test container discovery, validation, and backup orchestration
- **Runner Tests** (`baktainer_spec.rb`): Test the main application runner, thread pool, and scheduling

Unit tests use mocks and stubs to isolate functionality and run quickly without external dependencies.

### Integration Tests

Integration tests validate the complete backup workflow with real Docker containers:

- **Container Discovery**: Test finding containers with backup labels
- **Database Backups**: Test actual backup creation for PostgreSQL, MySQL, and SQLite
- **Error Handling**: Test graceful handling of failures and edge cases
- **Concurrent Execution**: Test thread pool and concurrent backup execution

Integration tests require Docker and may take longer to run.

## Test Environment Setup

### Dependencies

Install test dependencies:

```bash
cd app
bundle install
```

Required gems for testing:
- `rspec` - Testing framework
- `simplecov` - Code coverage reporting
- `factory_bot` - Test data factories
- `webmock` - HTTP request stubbing

### Test Database Containers

Integration tests use Docker containers defined in `spec/fixtures/docker-compose.test.yml`:

- PostgreSQL container with test database
- MySQL container with test database  
- SQLite container with test database file
- Control container without backup labels

Start test containers:

```bash
cd app
docker-compose -f spec/fixtures/docker-compose.test.yml up -d
```

Stop test containers:

```bash
cd app
docker-compose -f spec/fixtures/docker-compose.test.yml down -v
```

## Test Configuration

### RSpec Configuration (`.rspec`)

```
--require spec_helper
--format documentation
--color
--profile 10
--order random
```

### Coverage Configuration

Test coverage is configured in `spec/support/coverage.rb`:

- Minimum coverage: 80%
- Minimum per-file coverage: 70%
- HTML and console output formats
- Branch coverage tracking (Ruby 2.5+)
- Coverage tracking over time

Enable coverage:

```bash
COVERAGE=true bundle exec rspec
```

### Environment Variables

Tests clean up environment variables between runs and use temporary directories for backup files.

## Writing Tests

### Unit Test Example

```ruby
RSpec.describe Baktainer::BackupCommand do
  describe '.postgres' do
    it 'generates correct pg_dump command' do
      result = described_class.postgres(login: 'user', password: 'pass', database: 'testdb')
      
      expect(result).to be_a(Hash)
      expect(result[:env]).to eq(['PGPASSWORD=pass'])
      expect(result[:cmd]).to eq(['pg_dump', '-U', 'user', '-d', 'testdb'])
    end
  end
end
```

### Integration Test Example

```ruby
RSpec.describe 'PostgreSQL Backup', :integration do
  let(:postgres_container) do
    containers = Baktainer::Containers.find_all
    containers.find { |c| c.engine == 'postgres' }
  end

  it 'creates a valid PostgreSQL backup' do
    postgres_container.backup
    
    backup_files = Dir.glob(File.join(test_backup_dir, '**', '*.sql'))
    expect(backup_files).not_to be_empty
    
    backup_content = File.read(backup_files.first)
    expect(backup_content).to include('PostgreSQL database dump')
  end
end
```

### Test Helpers

Use test helpers defined in `spec_helper.rb`:

```ruby
# Create mock Docker container
container = mock_docker_container(labels)

# Create temporary backup directory
test_dir = create_test_backup_dir

# Set environment variables for test
with_env('BT_BACKUP_DIR' => test_dir) do
  # test code
end
```

## Continuous Integration

### GitHub Actions

Add to `.github/workflows/test.yml`:

```yaml
name: Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: 3.3
          bundler-cache: true
      - name: Run tests
        run: |
          cd app
          COVERAGE=true bundle exec rspec
      - name: Upload coverage
        uses: codecov/codecov-action@v3
```

### Coverage Reporting

Coverage reports are generated in `coverage/` directory:

- `coverage/index.html` - HTML report
- `coverage/coverage.json` - JSON data
- Console summary during test runs

## Troubleshooting

### Common Issues

1. **Docker containers not starting**: Check Docker daemon is running and ports are available
2. **Permission errors**: Ensure test script is executable (`chmod +x bin/test`)
3. **Bundle errors**: Run `bundle install` in the `app` directory
4. **Coverage not working**: Set `COVERAGE=true` environment variable

### Debugging Tests

```bash
# Run specific test file
bundle exec rspec spec/unit/container_spec.rb

# Run specific test
bundle exec rspec spec/unit/container_spec.rb:45

# Run with debug output
bundle exec rspec --format documentation --backtrace

# Run integration tests with container logs
docker-compose -f spec/fixtures/docker-compose.test.yml logs
```

### Performance

- Unit tests should complete in under 10 seconds
- Integration tests may take 30-60 seconds including container startup
- Use `bin/test --unit` for quick feedback during development
- Run full test suite before committing changes

## Best Practices

1. **Isolation**: Each test should be independent and clean up after itself
2. **Descriptive Names**: Use clear, descriptive test names and descriptions
3. **Mock External Dependencies**: Use mocks for Docker API calls in unit tests
4. **Test Error Conditions**: Include tests for error handling and edge cases
5. **Coverage**: Aim for high test coverage, especially for critical backup logic
6. **Fast Feedback**: Keep unit tests fast for quick development feedback