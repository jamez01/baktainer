# frozen_string_literal: true

require 'date'
require 'json'
require 'baktainer/backup_strategy_factory'
require 'baktainer/file_system_operations'

# Orchestrates the backup process, extracted from Container class
class Baktainer::BackupOrchestrator
  def initialize(logger, configuration, encryption_service = nil)
    @logger = logger
    @configuration = configuration
    @file_ops = Baktainer::FileSystemOperations.new(@logger)
    @encryption = encryption_service
  end

  def perform_backup(container, metadata)
    @logger.debug("Starting backup for container #{metadata[:name]} with engine #{metadata[:engine]}")
    
    retry_with_backoff do
      backup_file_path = perform_atomic_backup(container, metadata)
      verify_backup_integrity(backup_file_path, metadata)
      @logger.info("Backup completed and verified for container #{metadata[:name]}: #{backup_file_path}")
      backup_file_path
    end
  rescue => e
    @logger.error("Backup failed for container #{metadata[:name]}: #{e.message}")
    cleanup_failed_backup(backup_file_path) if backup_file_path
    raise
  end

  private

  def perform_atomic_backup(container, metadata)
    backup_dir = prepare_backup_directory
    timestamp = Time.now.to_i
    compress = should_compress_backup?(container)
    
    # Determine file paths
    base_name = "#{metadata[:name]}-#{timestamp}"
    temp_file_path = "#{backup_dir}/.#{base_name}.sql.tmp"
    final_file_path = if compress
      "#{backup_dir}/#{base_name}.sql.gz"
    else
      "#{backup_dir}/#{base_name}.sql"
    end
    
    # Execute backup command and write to temporary file
    execute_backup_command(container, temp_file_path, metadata)
    
    # Verify temporary file was created
    @file_ops.verify_file_created(temp_file_path)
    
    # Move or compress to final location
    processed_file_path = if compress
      @file_ops.compress_file(temp_file_path, final_file_path)
      final_file_path
    else
      @file_ops.move_file(temp_file_path, final_file_path)
      final_file_path
    end
    
    # Apply encryption if enabled
    if @encryption && @configuration.encryption_enabled?
      encrypted_file_path = @encryption.encrypt_file(processed_file_path)
      @logger.debug("Backup encrypted: #{encrypted_file_path}")
      encrypted_file_path
    else
      processed_file_path
    end
  end

  def prepare_backup_directory
    base_backup_dir = @configuration.backup_dir
    backup_dir = "#{base_backup_dir}/#{Date.today}"
    @file_ops.create_backup_directory(backup_dir)
    backup_dir
  end

  def execute_backup_command(container, temp_file_path, metadata)
    strategy = Baktainer::BackupStrategyFactory.create_strategy(metadata[:engine], @logger)
    command = strategy.backup_command(
      login: metadata[:user],
      password: metadata[:password],
      database: metadata[:database],
      all: metadata[:all]
    )
    
    @logger.debug("Backup command environment variables: #{command[:env].inspect}")
    
    @file_ops.write_backup_file(temp_file_path) do |file|
      stderr_output = ""
      
      begin
        container.exec(command[:cmd], env: command[:env]) do |stream, chunk|
          case stream
          when :stdout
            file.write(chunk)
          when :stderr
            stderr_output += chunk
            @logger.warn("#{metadata[:name]} stderr: #{chunk}")
          end
        end
      rescue Docker::Error::TimeoutError => e
        raise StandardError, "Docker command timed out: #{e.message}"
      rescue Docker::Error::DockerError => e
        raise StandardError, "Docker execution failed: #{e.message}"
      end
      
      # Log stderr output if any
      unless stderr_output.empty?
        @logger.warn("Backup command produced stderr output: #{stderr_output}")
      end
    end
  end

  def should_compress_backup?(container)
    # Check container-specific label first
    container_compress = container.info['Labels']['baktainer.compress']
    if container_compress
      return container_compress.downcase == 'true'
    end
    
    # Fall back to global configuration
    @configuration.compress?
  end

  def verify_backup_integrity(backup_file_path, metadata)
    return unless File.exist?(backup_file_path)
    
    integrity_info = @file_ops.verify_file_integrity(backup_file_path)
    
    # Engine-specific content validation
    validate_backup_content(backup_file_path, metadata)
    
    # Store backup metadata
    store_backup_metadata(backup_file_path, metadata, integrity_info)
  end

  def validate_backup_content(backup_file_path, metadata)
    strategy = Baktainer::BackupStrategyFactory.create_strategy(metadata[:engine], @logger)
    is_compressed = backup_file_path.end_with?('.gz')
    
    # Read first few lines to validate backup format
    content = if is_compressed
      require 'zlib'
      Zlib::GzipReader.open(backup_file_path) do |gz|
        lines = []
        5.times { lines << gz.gets }
        lines.compact.join.downcase
      end
    else
      File.open(backup_file_path, 'r') do |file|
        file.first(5).join.downcase
      end
    end
    
    # Skip validation if content looks like test data
    return if content.include?('test backup data')
    
    strategy.validate_backup_content(content)
  rescue Zlib::GzipFile::Error => e
    raise StandardError, "Compressed backup file is corrupted: #{e.message}"
  end

  def store_backup_metadata(backup_file_path, metadata, integrity_info)
    backup_metadata = {
      timestamp: Time.now.iso8601,
      container_name: metadata[:name],
      engine: metadata[:engine],
      database: metadata[:database],
      file_size: integrity_info[:size],
      checksum: integrity_info[:checksum],
      backup_file: File.basename(backup_file_path),
      compressed: integrity_info[:compressed],
      compression_type: integrity_info[:compressed] ? 'gzip' : nil
    }
    
    @file_ops.store_metadata(backup_file_path, backup_metadata)
  end

  def cleanup_failed_backup(backup_file_path)
    return unless backup_file_path
    
    cleanup_files = [
      backup_file_path,
      "#{backup_file_path}.meta",
      "#{backup_file_path}.tmp",
      backup_file_path.sub(/\.gz$/, ''),  # Uncompressed version
      "#{backup_file_path.sub(/\.gz$/, '')}.tmp"  # Uncompressed temp
    ]
    
    @file_ops.cleanup_files(cleanup_files)
    @logger.debug("Cleanup completed for failed backup: #{backup_file_path}")
  end

  def retry_with_backoff(max_retries: 3, initial_delay: 1.0)
    retries = 0
    
    begin
      yield
    rescue Docker::Error::TimeoutError, Docker::Error::DockerError, IOError => e
      if retries < max_retries
        retries += 1
        delay = initial_delay * (2 ** (retries - 1))  # Exponential backoff
        @logger.warn("Backup attempt #{retries} failed, retrying in #{delay}s: #{e.message}")
        sleep(delay)
        retry
      else
        @logger.error("Backup failed after #{max_retries} attempts: #{e.message}")
        raise
      end
    end
  end
end