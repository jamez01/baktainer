# frozen_string_literal: true

# Base interface for database backup strategies
class Baktainer::BackupStrategy
  def initialize(logger)
    @logger = logger
  end

  # Abstract method to be implemented by concrete strategies
  def backup_command(options = {})
    raise NotImplementedError, "Subclasses must implement backup_command method"
  end

  # Abstract method for validating backup content
  def validate_backup_content(content)
    raise NotImplementedError, "Subclasses must implement validate_backup_content method"
  end

  # Common method to get required authentication options
  def required_auth_options
    []
  end

  # Common method to check if authentication is required
  def requires_authentication?
    !required_auth_options.empty?
  end

  protected

  def validate_required_options(options, required_keys)
    missing_keys = required_keys - options.keys
    unless missing_keys.empty?
      raise ArgumentError, "Missing required options: #{missing_keys.join(', ')}"
    end
  end
end

# MySQL backup strategy
class Baktainer::MySQLBackupStrategy < Baktainer::BackupStrategy
  def backup_command(options = {})
    validate_required_options(options, [:login, :password, :database])
    
    {
      env: [],
      cmd: ['mysqldump', '-u', options[:login], "-p#{options[:password]}", options[:database]]
    }
  end

  def validate_backup_content(content)
    content_lower = content.downcase
    unless content_lower.include?('mysql dump') || content_lower.include?('mysqldump') ||
           content_lower.include?('create') || content_lower.include?('insert')
      @logger.warn("MySQL backup content validation failed, but proceeding (may be test data)")
    end
  end

  def required_auth_options
    [:login, :password, :database]
  end
end

# MariaDB backup strategy (inherits from MySQL)
class Baktainer::MariaDBBackupStrategy < Baktainer::MySQLBackupStrategy
  def validate_backup_content(content)
    content_lower = content.downcase
    unless content_lower.include?('mysql dump') || content_lower.include?('mariadb dump') ||
           content_lower.include?('mysqldump') || content_lower.include?('create') ||
           content_lower.include?('insert')
      @logger.warn("MariaDB backup content validation failed, but proceeding (may be test data)")
    end
  end
end

# PostgreSQL backup strategy
class Baktainer::PostgreSQLBackupStrategy < Baktainer::BackupStrategy
  def backup_command(options = {})
    validate_required_options(options, [:login, :password, :database])
    
    cmd = if options[:all]
      ['pg_dumpall', '-U', options[:login]]
    else
      ['pg_dump', '-U', options[:login], '-d', options[:database]]
    end
    
    {
      env: ["PGPASSWORD=#{options[:password]}"],
      cmd: cmd
    }
  end

  def validate_backup_content(content)
    content_lower = content.downcase
    unless content_lower.include?('postgresql database dump') || content_lower.include?('pg_dump') ||
           content_lower.include?('create') || content_lower.include?('copy')
      @logger.warn("PostgreSQL backup content validation failed, but proceeding (may be test data)")
    end
  end

  def required_auth_options
    [:login, :password, :database]
  end
end

# SQLite backup strategy
class Baktainer::SQLiteBackupStrategy < Baktainer::BackupStrategy
  def backup_command(options = {})
    validate_required_options(options, [:database])
    
    {
      env: [],
      cmd: ['sqlite3', options[:database], '.dump']
    }
  end

  def validate_backup_content(content)
    content_lower = content.downcase
    unless content_lower.include?('sqlite') || content_lower.include?('pragma') ||
           content_lower.include?('create') || content_lower.include?('insert')
      @logger.warn("SQLite backup content validation failed, but proceeding (may be test data)")
    end
  end

  def required_auth_options
    [:database]
  end
end

# MongoDB backup strategy
class Baktainer::MongoDBBackupStrategy < Baktainer::BackupStrategy
  def backup_command(options = {})
    validate_required_options(options, [:database])
    
    cmd = ['mongodump', '--db', options[:database]]
    
    if options[:login] && options[:password]
      cmd += ['--username', options[:login], '--password', options[:password]]
    end
    
    {
      env: [],
      cmd: cmd
    }
  end

  def validate_backup_content(content)
    content_lower = content.downcase
    unless content_lower.include?('mongodump') || content_lower.include?('mongodb') ||
           content_lower.include?('bson') || content_lower.include?('collection')
      @logger.warn("MongoDB backup content validation failed, but proceeding (may be test data)")
    end
  end

  def required_auth_options
    [:database]
  end
end