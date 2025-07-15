# Baktainer API Documentation

## Overview

Baktainer provides a comprehensive Ruby API for automated database backups in Docker environments. This documentation covers all public classes, methods, and configuration options.

## Core Classes

### Baktainer::Configuration

Manages application configuration with environment variable support and validation.

#### Constructor

```ruby
config = Baktainer::Configuration.new(env_vars = ENV)
```

#### Methods

##### `#docker_url`
Returns the Docker API URL.

**Returns:** `String`

##### `#ssl_enabled?`
Checks if SSL is enabled for Docker connections.

**Returns:** `Boolean`

##### `#compress?`
Checks if backup compression is enabled.

**Returns:** `Boolean`

##### `#ssl_options`
Returns SSL configuration options for Docker client.

**Returns:** `Hash`

##### `#to_h`
Returns configuration as a hash.

**Returns:** `Hash`

##### `#validate!`
Validates configuration and raises errors for invalid values.

**Returns:** `self`
**Raises:** `Baktainer::ConfigurationError`

#### Configuration Options

| Option | Environment Variable | Default | Description |
|--------|---------------------|---------|-------------|
| `docker_url` | `BT_DOCKER_URL` | `unix:///var/run/docker.sock` | Docker API endpoint |
| `cron_schedule` | `BT_CRON` | `0 0 * * *` | Backup schedule |
| `threads` | `BT_THREADS` | `4` | Thread pool size |
| `log_level` | `BT_LOG_LEVEL` | `info` | Logging level |
| `backup_dir` | `BT_BACKUP_DIR` | `/backups` | Backup directory |
| `compress` | `BT_COMPRESS` | `true` | Enable compression |
| `ssl_enabled` | `BT_SSL` | `false` | Enable SSL |
| `ssl_ca` | `BT_CA` | `nil` | CA certificate |
| `ssl_cert` | `BT_CERT` | `nil` | Client certificate |
| `ssl_key` | `BT_KEY` | `nil` | Client key |

#### Example

```ruby
config = Baktainer::Configuration.new
puts config.docker_url
puts config.compress?
puts config.to_h
```

### Baktainer::BackupStrategy

Abstract base class for database backup strategies.

#### Methods

##### `#backup_command(options = {})`
Abstract method to generate backup command.

**Parameters:**
- `options` (Hash): Database connection options

**Returns:** `Hash` with `:env` and `:cmd` keys
**Raises:** `NotImplementedError`

##### `#validate_backup_content(content)`
Abstract method to validate backup content.

**Parameters:**
- `content` (String): Backup file content

**Raises:** `NotImplementedError`

##### `#required_auth_options`
Returns required authentication options.

**Returns:** `Array<Symbol>`

##### `#requires_authentication?`
Checks if authentication is required.

**Returns:** `Boolean`

### Baktainer::MySQLBackupStrategy

MySQL database backup strategy.

#### Methods

##### `#backup_command(options = {})`
Generates MySQL backup command.

**Parameters:**
- `options` (Hash): Required keys: `:login`, `:password`, `:database`

**Returns:** `Hash`

**Example:**
```ruby
strategy = Baktainer::MySQLBackupStrategy.new(logger)
command = strategy.backup_command(
  login: 'root',
  password: 'secret',
  database: 'mydb'
)
# => { env: [], cmd: ['mysqldump', '-u', 'root', '-psecret', 'mydb'] }
```

### Baktainer::PostgreSQLBackupStrategy

PostgreSQL database backup strategy.

#### Methods

##### `#backup_command(options = {})`
Generates PostgreSQL backup command.

**Parameters:**
- `options` (Hash): Required keys: `:login`, `:password`, `:database`
- `options[:all]` (Boolean): Optional, use pg_dumpall if true

**Returns:** `Hash`

**Example:**
```ruby
strategy = Baktainer::PostgreSQLBackupStrategy.new(logger)
command = strategy.backup_command(
  login: 'postgres',
  password: 'secret',
  database: 'mydb'
)
# => { env: ['PGPASSWORD=secret'], cmd: ['pg_dump', '-U', 'postgres', '-d', 'mydb'] }
```

### Baktainer::SQLiteBackupStrategy

SQLite database backup strategy.

#### Methods

##### `#backup_command(options = {})`
Generates SQLite backup command.

**Parameters:**
- `options` (Hash): Required keys: `:database`

**Returns:** `Hash`

**Example:**
```ruby
strategy = Baktainer::SQLiteBackupStrategy.new(logger)
command = strategy.backup_command(database: '/data/mydb.sqlite')
# => { env: [], cmd: ['sqlite3', '/data/mydb.sqlite', '.dump'] }
```

### Baktainer::BackupStrategyFactory

Factory for creating backup strategies.

#### Class Methods

##### `#create_strategy(engine, logger)`
Creates a backup strategy for the specified engine.

**Parameters:**
- `engine` (String/Symbol): Database engine type
- `logger` (Logger): Logger instance

**Returns:** `Baktainer::BackupStrategy`
**Raises:** `Baktainer::UnsupportedEngineError`

##### `#supported_engines`
Returns list of supported database engines.

**Returns:** `Array<String>`

##### `#supports_engine?(engine)`
Checks if engine is supported.

**Parameters:**
- `engine` (String/Symbol): Database engine type

**Returns:** `Boolean`

##### `#register_strategy(engine, strategy_class)`
Registers a custom backup strategy.

**Parameters:**
- `engine` (String): Engine name
- `strategy_class` (Class): Strategy class inheriting from BackupStrategy

**Example:**
```ruby
factory = Baktainer::BackupStrategyFactory
strategy = factory.create_strategy('mysql', logger)
puts factory.supported_engines
# => ['mysql', 'mariadb', 'postgres', 'postgresql', 'sqlite', 'mongodb']
```

### Baktainer::BackupMonitor

Monitors backup operations and tracks performance metrics.

#### Constructor

```ruby
monitor = Baktainer::BackupMonitor.new(logger)
```

#### Methods

##### `#start_backup(container_name, engine)`
Starts monitoring a backup operation.

**Parameters:**
- `container_name` (String): Container name
- `engine` (String): Database engine

##### `#complete_backup(container_name, file_path, file_size = nil)`
Records successful backup completion.

**Parameters:**
- `container_name` (String): Container name
- `file_path` (String): Backup file path
- `file_size` (Integer): Optional file size

##### `#fail_backup(container_name, error_message)`
Records backup failure.

**Parameters:**
- `container_name` (String): Container name
- `error_message` (String): Error message

##### `#get_metrics_summary`
Returns overall backup metrics.

**Returns:** `Hash`

##### `#get_container_metrics(container_name)`
Returns metrics for specific container.

**Parameters:**
- `container_name` (String): Container name

**Returns:** `Hash` or `nil`

##### `#export_metrics(format = :json)`
Exports metrics in specified format.

**Parameters:**
- `format` (Symbol): Export format (`:json` or `:csv`)

**Returns:** `String`

**Example:**
```ruby
monitor = Baktainer::BackupMonitor.new(logger)
monitor.start_backup('myapp', 'mysql')
monitor.complete_backup('myapp', '/backups/myapp.sql.gz', 1024)
puts monitor.get_metrics_summary
```

### Baktainer::DynamicThreadPool

Dynamic thread pool with automatic sizing and monitoring.

#### Constructor

```ruby
pool = Baktainer::DynamicThreadPool.new(
  min_threads: 2,
  max_threads: 20,
  initial_size: 4,
  logger: logger
)
```

#### Methods

##### `#post(&block)`
Submits a task to the thread pool.

**Parameters:**
- `block` (Proc): Task to execute

**Returns:** `Concurrent::Future`

##### `#statistics`
Returns thread pool statistics.

**Returns:** `Hash`

##### `#force_resize(new_size)`
Manually resizes the thread pool.

**Parameters:**
- `new_size` (Integer): New thread pool size

##### `#shutdown`
Shuts down the thread pool.

**Example:**
```ruby
pool = Baktainer::DynamicThreadPool.new(logger: logger)
future = pool.post { expensive_operation }
result = future.value
puts pool.statistics
pool.shutdown
```

### Baktainer::DependencyContainer

Dependency injection container for managing application dependencies.

#### Constructor

```ruby
container = Baktainer::DependencyContainer.new
```

#### Methods

##### `#register(name, &factory)`
Registers a service factory.

**Parameters:**
- `name` (String/Symbol): Service name
- `factory` (Proc): Factory block

##### `#singleton(name, &factory)`
Registers a singleton service.

**Parameters:**
- `name` (String/Symbol): Service name
- `factory` (Proc): Factory block

##### `#get(name)`
Gets a service instance.

**Parameters:**
- `name` (String/Symbol): Service name

**Returns:** Service instance
**Raises:** `Baktainer::ServiceNotFoundError`

##### `#configure`
Configures the container with standard services.

**Returns:** `self`

##### `#reset!`
Resets all services (useful for testing).

**Example:**
```ruby
container = Baktainer::DependencyContainer.new.configure
logger = container.get(:logger)
config = container.get(:configuration)
```

### Baktainer::StreamingBackupHandler

Memory-optimized streaming backup handler for large databases.

#### Constructor

```ruby
handler = Baktainer::StreamingBackupHandler.new(logger)
```

#### Methods

##### `#stream_backup(container, command, output_path, compress: true, &block)`
Streams backup data with memory optimization.

**Parameters:**
- `container` (Docker::Container): Docker container
- `command` (Hash): Backup command
- `output_path` (String): Output file path
- `compress` (Boolean): Enable compression
- `block` (Proc): Optional progress callback

**Returns:** `Integer` (total bytes written)

**Example:**
```ruby
handler = Baktainer::StreamingBackupHandler.new(logger)
bytes_written = handler.stream_backup(container, command, '/tmp/backup.sql.gz') do |chunk_size|
  puts "Wrote #{chunk_size} bytes"
end
```

## Error Classes

### Baktainer::ConfigurationError
Raised when configuration is invalid.

### Baktainer::ValidationError
Raised when container validation fails.

### Baktainer::UnsupportedEngineError
Raised when database engine is not supported.

### Baktainer::ServiceNotFoundError
Raised when requested service is not found in dependency container.

### Baktainer::MemoryLimitError
Raised when memory usage exceeds limits during streaming backup.

## Usage Examples

### Basic Usage

```ruby
# Create configuration
config = Baktainer::Configuration.new

# Set up dependency container
container = Baktainer::DependencyContainer.new.configure

# Get services
logger = container.get(:logger)
monitor = container.get(:backup_monitor)
thread_pool = container.get(:thread_pool)

# Create backup strategy
strategy = Baktainer::BackupStrategyFactory.create_strategy('mysql', logger)

# Start monitoring
monitor.start_backup('myapp', 'mysql')

# Execute backup
command = strategy.backup_command(login: 'root', password: 'secret', database: 'mydb')
# ... execute backup ...

# Complete monitoring
monitor.complete_backup('myapp', '/backups/myapp.sql.gz')

# Get metrics
puts monitor.get_metrics_summary
```

### Custom Backup Strategy

```ruby
class CustomBackupStrategy < Baktainer::BackupStrategy
  def backup_command(options = {})
    validate_required_options(options, [:database])
    
    {
      env: [],
      cmd: ['custom-backup-tool', options[:database]]
    }
  end
  
  def validate_backup_content(content)
    unless content.include?('custom-backup-header')
      @logger.warn("Custom backup validation failed")
    end
  end
end

# Register custom strategy
Baktainer::BackupStrategyFactory.register_strategy('custom', CustomBackupStrategy)

# Use custom strategy
strategy = Baktainer::BackupStrategyFactory.create_strategy('custom', logger)
```

### Testing with Dependency Injection

```ruby
# Override dependencies for testing
container = Baktainer::DependencyContainer.new.configure
mock_logger = double('Logger')
container.override_logger(mock_logger)

# Use mocked logger
logger = container.get(:logger)
```

## Performance Considerations

1. **Memory Usage**: Use `StreamingBackupHandler` for large databases to minimize memory usage
2. **Thread Pool**: Configure appropriate `min_threads` and `max_threads` based on your workload
3. **Compression**: Enable compression for large backups to save disk space
4. **Monitoring**: Use `BackupMonitor` to track performance and identify bottlenecks

## Thread Safety

All classes are designed to be thread-safe for concurrent backup operations:
- `BackupMonitor` uses concurrent data structures
- `DynamicThreadPool` includes proper synchronization
- `DependencyContainer` singleton services are thread-safe
- `StreamingBackupHandler` is safe for concurrent use

## Logging

All classes accept a logger instance and provide detailed logging at different levels:
- `DEBUG`: Detailed execution information
- `INFO`: General operational information
- `WARN`: Warning conditions
- `ERROR`: Error conditions

Configure logging level via `BT_LOG_LEVEL` environment variable.