# Baktainer TODO List

This document tracks all identified issues, improvements, and future enhancements for the Baktainer project, organized by priority and category.

## 🚨 CRITICAL (Security & Data Integrity)

### Security Vulnerabilities
- [x] **Add command injection protection** ✅ COMPLETED
  - ✅ Implemented proper shell argument parsing with whitelist validation
  - ✅ Added command sanitization and security checks
  - ✅ Added comprehensive security tests

- [x] **Improve SSL/TLS certificate handling** ✅ COMPLETED
  - ✅ Added certificate validation and error handling
  - ✅ Implemented support for both file and environment variable certificates
  - ✅ Added certificate expiration and key matching validation

- [x] **Review Docker socket security** ✅ COMPLETED
  - ✅ Documented security implications in SECURITY.md
  - ✅ Provided Docker socket proxy alternatives
  - ✅ Added security warnings in README.md

### Data Integrity
- [x] **Add backup verification** ✅ COMPLETED
  - ✅ Implemented backup file integrity verification with SHA256 checksums
  - ✅ Added database engine-specific content validation
  - ✅ Created backup metadata storage for tracking

- [x] **Implement atomic backup operations** ✅ COMPLETED
  - ✅ Write to temporary files first, then atomically rename
  - ✅ Implemented cleanup for failed backup attempts
  - ✅ Added comprehensive error handling and rollback

## 🔥 HIGH PRIORITY (Reliability & Correctness)

### Critical Bug Fixes
- [ ] **Fix method name typos**
  - Fix `@cerificate` → `@certificate` in `app/lib/baktainer.rb:96`
  - Fix `posgres` → `postgres` in `app/lib/baktainer/postgres.rb:18`
  - Fix `validdate` → `validate` in `app/lib/baktainer/container.rb:54`

- [ ] **Fix SQLite API inconsistency** (`app/lib/baktainer/sqlite.rb`)
  - Convert SQLite class methods to instance methods
  - Ensure consistent API across all database engines
  - Update any calling code accordingly

### Error Handling & Recovery
- [ ] **Add comprehensive error handling for file operations** (`app/lib/baktainer/container.rb:74-82`)
  - Wrap all file I/O in proper exception handling
  - Handle disk space, permissions, and I/O errors gracefully
  - Add meaningful error messages for common failure scenarios

- [ ] **Implement proper resource cleanup**
  - Use `File.open` with blocks or ensure file handles are closed in `ensure` blocks
  - Add cleanup for temporary files and directories
  - Prevent resource leaks in thread pool operations

- [ ] **Add retry mechanisms for transient failures**
  - Implement exponential backoff for Docker API calls
  - Add retry logic for network-related backup failures
  - Configure maximum retry attempts and timeout values

- [ ] **Improve thread pool error handling** (`app/lib/baktainer.rb:59-69`)
  - Track failed backup attempts, not just log them
  - Implement backup status reporting
  - Add thread pool lifecycle management with proper shutdown

### Docker API Integration
- [ ] **Add Docker API error handling** (`app/lib/baktainer/container.rb:103-111`)
  - Handle Docker daemon connection failures
  - Add retry logic for Docker API timeouts
  - Provide clear error messages for Docker-related issues

- [ ] **Implement Docker connection health checks**
  - Verify Docker connectivity at startup
  - Add periodic health checks during operation
  - Graceful degradation when Docker is unavailable

## ⚠️ MEDIUM PRIORITY (Architecture & Maintainability)

### Code Architecture
- [ ] **Refactor Container class responsibilities** (`app/lib/baktainer/container.rb`)
  - Extract validation logic into separate class
  - Separate backup orchestration from container metadata
  - Create dedicated file system operations class

- [ ] **Implement Strategy pattern for database engines**
  - Create common interface for all database backup strategies
  - Ensure consistent method signatures across engines
  - Add factory pattern for engine instantiation

- [ ] **Add proper dependency injection**
  - Remove global LOGGER constant dependency
  - Inject Docker client instead of using global Docker.url
  - Make configuration injectable for better testing

- [ ] **Create Configuration management class**
  - Centralize all environment variable access
  - Add configuration validation at startup
  - Implement default value management

### Performance & Scalability
- [ ] **Implement dynamic thread pool sizing**
  - Allow thread pool size adjustment during runtime
  - Add monitoring for thread pool utilization
  - Implement backpressure mechanisms for high load

- [ ] **Add backup operation monitoring**
  - Track backup duration and success rates
  - Implement backup size monitoring
  - Add alerting for backup failures or performance degradation

- [ ] **Optimize memory usage for large backups**
  - Stream backup data instead of loading into memory
  - Implement backup compression options
  - Add memory usage monitoring and limits

## 📝 MEDIUM PRIORITY (Quality Assurance)

### Testing Infrastructure
- [x] **Set up testing framework** ✅ COMPLETED
  - ✅ Added RSpec testing framework to Gemfile
  - ✅ Configured test directory structure with unit and integration tests
  - ✅ Added test database containers for integration tests

- [x] **Write unit tests for core functionality** ✅ COMPLETED
  - ✅ Test all database backup command generation (including PostgreSQL aliases)
  - ✅ Test container discovery and validation logic
  - ✅ Test Runner class functionality and configuration

- [x] **Add integration tests** ✅ COMPLETED
  - ✅ Test full backup workflow with test containers
  - ✅ Test Docker API integration scenarios
  - ✅ Test error handling and recovery paths

- [x] **Implement test coverage reporting** ✅ COMPLETED
  - ✅ Added SimpleCov coverage tool
  - ✅ Achieved 94.94% line coverage (150/158 lines)
  - ✅ Added coverage reporting to test commands

### Documentation
- [ ] **Add comprehensive API documentation**
  - Document all public methods with YARD
  - Add usage examples for each database engine
  - Document configuration options and environment variables

- [ ] **Create troubleshooting guide**
  - Document common error scenarios and solutions
  - Add debugging techniques and tools
  - Create FAQ for deployment issues

## 🔧 LOW PRIORITY (Enhancements)

### Feature Enhancements
- [ ] **Implement backup rotation and cleanup**
  - Add configurable retention policies
  - Implement automatic cleanup of old backups
  - Add disk space monitoring and cleanup triggers

- [ ] **Add backup encryption support**
  - Implement backup file encryption at rest
  - Add key management for encrypted backups
  - Support multiple encryption algorithms

- [ ] **Enhance logging and monitoring**
  - Implement structured logging (JSON format)
  - Add metrics collection and export
  - Integrate with monitoring systems (Prometheus, etc.)

- [ ] **Add backup scheduling flexibility**
  - Support multiple backup schedules per container
  - Add one-time backup scheduling
  - Implement backup dependency management

### Operational Improvements
- [ ] **Add health check endpoints**
  - Implement HTTP health check endpoint
  - Add backup status reporting API
  - Create monitoring dashboard

- [ ] **Improve container label validation**
  - Add schema validation for backup labels
  - Provide helpful error messages for invalid configurations
  - Add label migration tools for schema changes

- [ ] **Add backup notification system**
  - Send notifications on backup completion/failure
  - Support multiple notification channels (email, Slack, webhooks)
  - Add configurable notification thresholds

### Developer Experience
- [ ] **Add development environment setup**
  - Create docker-compose for development
  - Add sample database containers for testing
  - Document local development workflow

- [ ] **Implement backup dry-run mode**
  - Add flag to simulate backups without execution
  - Show what would be backed up and where
  - Validate configuration without performing operations

- [ ] **Add CLI improvements**
  - Add more command-line options for debugging
  - Implement verbose/quiet modes
  - Add configuration validation command

## 📊 FUTURE CONSIDERATIONS

### Advanced Features
- [ ] **Support for additional database engines**
  - Add Redis backup support
  - Implement MongoDB backup improvements
  - Add support for InfluxDB and time-series databases

- [ ] **Implement backup verification and restoration**
  - Add automatic backup validation
  - Create restoration workflow and tools
  - Implement backup integrity checking

- [ ] **Add cloud storage integration**
  - Support for S3, GCS, Azure Blob storage
  - Implement backup replication across regions
  - Add cloud-native backup encryption

- [ ] **Enhance container discovery**
  - Support for Kubernetes pod discovery
  - Add support for Docker Swarm services
  - Implement custom discovery plugins

---

## Priority Legend
- 🚨 **CRITICAL**: Security vulnerabilities, data integrity issues
- 🔥 **HIGH**: Bugs, reliability issues, core functionality problems
- ⚠️ **MEDIUM**: Architecture improvements, maintainability
- 📝 **MEDIUM**: Quality assurance, testing, documentation
- 🔧 **LOW**: Feature enhancements, nice-to-have improvements
- 📊 **FUTURE**: Advanced features for consideration

## Getting Started
1. Begin with CRITICAL security issues
2. Fix HIGH priority bugs and reliability issues
3. Add testing infrastructure before making architectural changes
4. Implement MEDIUM priority improvements incrementally
5. Consider LOW priority enhancements based on user feedback

For each TODO item, create a separate branch, implement the fix, add tests, and ensure all existing functionality continues to work before merging.
