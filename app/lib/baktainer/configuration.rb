# frozen_string_literal: true

# Configuration management class for Baktainer
# Centralizes all environment variable access and provides validation
class Baktainer::Configuration
  # Configuration constants with defaults
  DEFAULTS = {
    docker_url: 'unix:///var/run/docker.sock',
    cron_schedule: '0 0 * * *',
    threads: 4,
    log_level: 'info',
    backup_dir: '/backups',
    compress: true,
    ssl_enabled: false,
    ssl_ca: nil,
    ssl_cert: nil,
    ssl_key: nil,
    rotation_enabled: true,
    retention_days: 30,
    retention_count: 0,
    min_free_space_gb: 10,
    encryption_enabled: false,
    encryption_key: nil,
    encryption_key_file: nil,
    encryption_passphrase: nil,
    key_rotation_enabled: false
  }.freeze

  # Environment variable mappings
  ENV_MAPPINGS = {
    docker_url: 'BT_DOCKER_URL',
    cron_schedule: 'BT_CRON',
    threads: 'BT_THREADS',
    log_level: 'BT_LOG_LEVEL',
    backup_dir: 'BT_BACKUP_DIR',
    compress: 'BT_COMPRESS',
    ssl_enabled: 'BT_SSL',
    ssl_ca: 'BT_CA',
    ssl_cert: 'BT_CERT',
    ssl_key: 'BT_KEY',
    rotation_enabled: 'BT_ROTATION_ENABLED',
    retention_days: 'BT_RETENTION_DAYS',
    retention_count: 'BT_RETENTION_COUNT',
    min_free_space_gb: 'BT_MIN_FREE_SPACE_GB',
    encryption_enabled: 'BT_ENCRYPTION_ENABLED',
    encryption_key: 'BT_ENCRYPTION_KEY',
    encryption_key_file: 'BT_ENCRYPTION_KEY_FILE',
    encryption_passphrase: 'BT_ENCRYPTION_PASSPHRASE',
    key_rotation_enabled: 'BT_KEY_ROTATION_ENABLED'
  }.freeze

  # Valid log levels
  VALID_LOG_LEVELS = %w[debug info warn error].freeze

  attr_reader :docker_url, :cron_schedule, :threads, :log_level, :backup_dir,
              :compress, :ssl_enabled, :ssl_ca, :ssl_cert, :ssl_key,
              :rotation_enabled, :retention_days, :retention_count, :min_free_space_gb,
              :encryption_enabled, :encryption_key, :encryption_key_file, :encryption_passphrase,
              :key_rotation_enabled

  def initialize(env_vars = ENV)
    @env_vars = env_vars
    load_configuration
    validate_configuration
  end

  # Check if SSL is enabled
  def ssl_enabled?
    @ssl_enabled == true || @ssl_enabled == 'true'
  end

  # Check if encryption is enabled
  def encryption_enabled?
    @encryption_enabled == true || @encryption_enabled == 'true'
  end

  # Check if key rotation is enabled
  def key_rotation_enabled?
    @key_rotation_enabled == true || @key_rotation_enabled == 'true'
  end

  # Check if compression is enabled
  def compress?
    @compress == true || @compress == 'true'
  end

  # Get SSL options hash for Docker client
  def ssl_options
    return {} unless ssl_enabled?

    {
      ca_file: ssl_ca,
      cert_file: ssl_cert,
      key_file: ssl_key
    }.compact
  end

  # Get configuration as hash
  def to_h
    {
      docker_url: docker_url,
      cron_schedule: cron_schedule,
      threads: threads,
      log_level: log_level,
      backup_dir: backup_dir,
      compress: compress?,
      ssl_enabled: ssl_enabled?,
      ssl_ca: ssl_ca,
      ssl_cert: ssl_cert,
      ssl_key: ssl_key
    }
  end

  # Validate configuration and raise errors for invalid values
  def validate!
    validate_configuration
    self
  end

  private

  def load_configuration
    @docker_url = get_env_value(:docker_url)
    @cron_schedule = get_env_value(:cron_schedule)
    @threads = get_env_value(:threads, :integer)
    @log_level = get_env_value(:log_level)
    @backup_dir = get_env_value(:backup_dir)
    @compress = get_env_value(:compress, :boolean)
    @ssl_enabled = get_env_value(:ssl_enabled, :boolean)
    @ssl_ca = get_env_value(:ssl_ca)
    @ssl_cert = get_env_value(:ssl_cert)
    @ssl_key = get_env_value(:ssl_key)
    @rotation_enabled = get_env_value(:rotation_enabled, :boolean)
    @retention_days = get_env_value(:retention_days, :integer)
    @retention_count = get_env_value(:retention_count, :integer)
    @min_free_space_gb = get_env_value(:min_free_space_gb, :integer)
    @encryption_enabled = get_env_value(:encryption_enabled, :boolean)
    @encryption_key = get_env_value(:encryption_key)
    @encryption_key_file = get_env_value(:encryption_key_file)
    @encryption_passphrase = get_env_value(:encryption_passphrase)
    @key_rotation_enabled = get_env_value(:key_rotation_enabled, :boolean)
  end

  def get_env_value(key, type = :string)
    env_key = ENV_MAPPINGS[key]
    value = @env_vars[env_key]
    
    # Use default if no environment variable is set
    if value.nil? || value.empty?
      return DEFAULTS[key]
    end

    case type
    when :integer
      begin
        Integer(value)
      rescue ArgumentError
        raise ConfigurationError, "Invalid integer value for #{env_key}: #{value}"
      end
    when :boolean
      case value.downcase
      when 'true', '1', 'yes', 'on'
        true
      when 'false', '0', 'no', 'off'
        false
      else
        raise ConfigurationError, "Invalid boolean value for #{env_key}: #{value}"
      end
    when :string
      value
    else
      value
    end
  end

  def validate_configuration
    validate_docker_url
    validate_cron_schedule
    validate_threads
    validate_log_level
    validate_backup_dir
    validate_ssl_configuration
    validate_rotation_configuration
    validate_encryption_configuration
  end

  def validate_docker_url
    unless docker_url.is_a?(String) && !docker_url.empty?
      raise ConfigurationError, "Docker URL must be a non-empty string"
    end

    # Basic validation for URL format
    valid_protocols = %w[unix tcp http https]
    unless valid_protocols.any? { |protocol| docker_url.start_with?("#{protocol}://") }
      raise ConfigurationError, "Docker URL must start with one of: #{valid_protocols.join(', ')}"
    end
  end

  def validate_cron_schedule
    unless cron_schedule.is_a?(String) && !cron_schedule.empty?
      raise ConfigurationError, "Cron schedule must be a non-empty string"
    end

    # Basic cron validation (5 fields separated by spaces)
    parts = cron_schedule.split(/\s+/)
    unless parts.length == 5
      raise ConfigurationError, "Cron schedule must have exactly 5 fields"
    end
  end

  def validate_threads
    unless threads.is_a?(Integer) && threads > 0
      raise ConfigurationError, "Thread count must be a positive integer"
    end

    if threads > 50
      raise ConfigurationError, "Thread count should not exceed 50 for safety"
    end
  end

  def validate_log_level
    unless VALID_LOG_LEVELS.include?(log_level.downcase)
      raise ConfigurationError, "Log level must be one of: #{VALID_LOG_LEVELS.join(', ')}"
    end
  end

  def validate_backup_dir
    unless backup_dir.is_a?(String) && !backup_dir.empty?
      raise ConfigurationError, "Backup directory must be a non-empty string"
    end

    # Check if it's an absolute path
    unless backup_dir.start_with?('/')
      raise ConfigurationError, "Backup directory must be an absolute path"
    end
  end

  def validate_ssl_configuration
    return unless ssl_enabled?

    missing_vars = []
    missing_vars << 'BT_CA' if ssl_ca.nil? || ssl_ca.empty?
    missing_vars << 'BT_CERT' if ssl_cert.nil? || ssl_cert.empty?
    missing_vars << 'BT_KEY' if ssl_key.nil? || ssl_key.empty?

    unless missing_vars.empty?
      raise ConfigurationError, "SSL is enabled but missing required variables: #{missing_vars.join(', ')}"
    end
  end

  def validate_rotation_configuration
    # Validate retention days
    unless retention_days.is_a?(Integer) && retention_days >= 0
      raise ConfigurationError, "Retention days must be a non-negative integer"
    end

    if retention_days > 365
      raise ConfigurationError, "Retention days should not exceed 365 for safety"
    end

    # Validate retention count
    unless retention_count.is_a?(Integer) && retention_count >= 0
      raise ConfigurationError, "Retention count must be a non-negative integer"
    end

    if retention_count > 1000
      raise ConfigurationError, "Retention count should not exceed 1000 for safety"
    end

    # Validate minimum free space
    unless min_free_space_gb.is_a?(Integer) && min_free_space_gb >= 0
      raise ConfigurationError, "Minimum free space must be a non-negative integer"
    end

    if min_free_space_gb > 1000
      raise ConfigurationError, "Minimum free space should not exceed 1000GB for safety"
    end

    # Ensure at least one retention policy is enabled
    if retention_days == 0 && retention_count == 0
      puts "Warning: Both retention policies are disabled, backups will accumulate indefinitely"
    end
  end

  def validate_encryption_configuration
    return unless encryption_enabled?

    # Check that at least one key source is provided
    key_sources = [encryption_key, encryption_key_file, encryption_passphrase].compact
    if key_sources.empty?
      raise ConfigurationError, "Encryption enabled but no key source provided. Set BT_ENCRYPTION_KEY, BT_ENCRYPTION_KEY_FILE, or BT_ENCRYPTION_PASSPHRASE"
    end

    # Validate key file exists if specified
    if encryption_key_file && !File.exist?(encryption_key_file)
      raise ConfigurationError, "Encryption key file not found: #{encryption_key_file}"
    end

    # Validate key file is readable
    if encryption_key_file && !File.readable?(encryption_key_file)
      raise ConfigurationError, "Encryption key file is not readable: #{encryption_key_file}"
    end

    # Warn about passphrase security
    if encryption_passphrase && encryption_passphrase.length < 12
      puts "Warning: Encryption passphrase is short. Consider using at least 12 characters for better security."
    end
  end
end

# Custom exception for configuration errors
class Baktainer::ConfigurationError < StandardError; end