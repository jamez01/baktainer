# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Baktainer is a Ruby-based Docker container database backup utility that automatically discovers and backs up databases using Docker labels. It supports MySQL, MariaDB, PostgreSQL, and SQLite databases.

## Development Commands

### Build and Run
```bash
# Build Docker image locally
docker build -t baktainer:local .

# Run with docker-compose
docker-compose up -d

# Run directly with Ruby (for development)
cd app && bundle install
bundle exec ruby app.rb

# Run backup immediately (bypasses cron schedule)
cd app && bundle exec ruby app.rb --now
```

### Dependency Management
```bash
cd app
bundle install              # Install dependencies
bundle update              # Update dependencies
bundle exec <command>      # Run commands with bundled gems
```

### Testing Commands
```bash
cd app

# Quick unit tests
bin/test
bundle exec rspec spec/unit/

# All tests with coverage
bin/test --all --coverage
COVERAGE=true bundle exec rspec

# Integration tests (requires Docker)
bin/test --integration --setup --cleanup
bundle exec rspec spec/integration/

# Using Rake tasks
rake spec                    # Unit tests
rake integration            # Integration tests  
rake test_full              # Full suite with setup/cleanup
rake coverage               # Tests with coverage
rake coverage_report        # Open coverage report
```

### Test Coverage
Current test coverage: **94.94% line coverage** (150/158 lines), **71.11% branch coverage** (32/45 branches)
- 66 test examples covering all major functionality
- Unit tests for all database engines, container discovery, and backup workflows  
- Integration tests with mocked Docker API calls
- Coverage report available at `coverage/index.html` after running tests with `COVERAGE=true`

### Docker Commands
```bash
# View logs
docker logs baktainer

# Restart container
docker restart baktainer

# Check running containers with baktainer labels
docker ps --filter "label=baktainer.backup=true"
```

## Architecture Overview

### Core Components

1. **Runner (`app/lib/baktainer.rb`)**
   - Main orchestrator class `Baktainer::Runner`
   - Manages Docker connection (socket/TCP/SSL)
   - Implements cron-based scheduling using `cron_calc` gem
   - Uses thread pool for concurrent backups

2. **Container Discovery (`app/lib/baktainer/container.rb`)**
   - `Baktainer::Containers.find_all` discovers containers with `baktainer.backup=true` label
   - Parses Docker labels to extract database configuration
   - Creates appropriate backup command objects

3. **Database Backup Implementations**
   - `app/lib/baktainer/mysql.rb` - MySQL/MariaDB backups using `mysqldump`
   - `app/lib/baktainer/postgres.rb` - PostgreSQL backups using `pg_dump`
   - `app/lib/baktainer/sqlite.rb` - SQLite backups using file copy
   - Each implements a common interface with `#backup` method

4. **Backup Command (`app/lib/baktainer/backup_command.rb`)**
   - Abstract base class for database-specific backup implementations
   - Handles file organization: `/backups/<date>/<name>-<timestamp>.sql`
   - Manages Docker exec operations

### Threading Model
- Uses `concurrent-ruby` gem with `FixedThreadPool`
- Default 4 threads (configurable via `BT_THREADS`)
- Each backup runs in separate thread
- Thread-safe logging via custom Logger wrapper

### Docker Integration
- Connects via Docker socket (`/var/run/docker.sock`) or TCP
- Supports SSL/TLS for remote Docker API
- Uses `docker-api` gem for container operations
- Executes backup commands inside containers via `docker exec`

## Environment Variables

Required configuration through environment variables:

- `BT_DOCKER_URL` - Docker API endpoint (default: `unix:///var/run/docker.sock`)
- `BT_CRON` - Cron expression for backup schedule (default: `0 0 * * *`)
- `BT_THREADS` - Thread pool size (default: 4)
- `BT_LOG_LEVEL` - Logging level: debug/info/warn/error (default: info)
- `BT_BACKUP_DIR` - Backup storage directory (default: `/backups`)
- `BT_SSL` - Enable SSL for Docker API (default: false)
- `BT_CA` - CA certificate for SSL
- `BT_CERT` - Client certificate for SSL
- `BT_KEY` - Client key for SSL

## Docker Label Configuration

Containers must have these labels for backup:

```yaml
labels:
  - baktainer.backup=true           # Required: Enable backup
  - baktainer.db.engine=<engine>    # Required: mysql/postgres/sqlite
  - baktainer.db.name=<database>    # Required: Database name
  - baktainer.db.user=<username>    # Required for MySQL/PostgreSQL
  - baktainer.db.password=<pass>    # Required for MySQL/PostgreSQL
  - baktainer.name=<app_name>       # Optional: Custom backup filename
```

## File Organization

Backups are stored as:
```
/backups/
├── YYYY-MM-DD/
│   ├── <name>-<unix_timestamp>.sql
│   └── <name>-<unix_timestamp>.sql
```

## Adding New Database Support

1. Create new file in `app/lib/baktainer/<database>.rb`
2. Inherit from `Baktainer::BackupCommand`
3. Implement `#backup` method
4. Add engine mapping in `container.rb`
5. Update README.md with new engine documentation

## Deployment

GitHub Actions automatically builds and pushes to Docker Hub on:
- Push to `main` branch → `jamez001/baktainer:latest`
- Tag push `v*.*.*` → `jamez001/baktainer:<version>`

Manual deployment:
```bash
docker build -t jamez001/baktainer:latest .
docker push jamez001/baktainer:latest
```

## Common Development Tasks

### Testing Database Backups
```bash
# Create test container with labels
docker run -d \
  --name test-postgres \
  -e POSTGRES_PASSWORD=testpass \
  -l baktainer.backup=true \
  -l baktainer.db.engine=postgres \
  -l baktainer.db.name=testdb \
  -l baktainer.db.user=postgres \
  -l baktainer.db.password=testpass \
  postgres:17

# Run backup immediately
cd app && bundle exec ruby app.rb --now

# Check backup file
ls -la backups/$(date +%Y-%m-%d)/
```

### Debugging
- Set `BT_LOG_LEVEL=debug` for verbose logging
- Check container logs: `docker logs baktainer`
- Verify Docker socket permissions
- Test Docker connection: `docker ps` from inside container

## Code Conventions

- Ruby 3.3 with frozen string literals
- Module namespacing under `Baktainer`
- Logger instance available as `LOGGER`
- Error handling with logged stack traces in debug mode
- No test framework currently implemented