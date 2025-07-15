# frozen_string_literal: true

require 'fileutils'
require 'digest'
require 'zlib'

# File system operations extracted from Container class
class Baktainer::FileSystemOperations
  def initialize(logger)
    @logger = logger
  end

  def create_backup_directory(path)
    FileUtils.mkdir_p(path) unless Dir.exist?(path)
    
    # Verify directory is writable
    unless File.writable?(path)
      raise IOError, "Backup directory is not writable: #{path}"
    end
    
    # Check available disk space (minimum 100MB)
    available_space = get_available_disk_space(path)
    if available_space < 100 * 1024 * 1024  # 100MB in bytes
      raise IOError, "Insufficient disk space in #{path}. Available: #{available_space / 1024 / 1024}MB"
    end
    
    @logger.debug("Created backup directory: #{path}")
  rescue Errno::EACCES => e
    raise IOError, "Permission denied creating backup directory #{path}: #{e.message}"
  rescue Errno::ENOSPC => e
    raise IOError, "No space left on device for backup directory #{path}: #{e.message}"
  rescue Errno::EIO => e
    raise IOError, "I/O error creating backup directory #{path}: #{e.message}"
  rescue SystemCallError => e
    raise IOError, "System error creating backup directory #{path}: #{e.message}"
  end

  def write_backup_file(file_path, &block)
    File.open(file_path, 'w') do |file|
      yield(file)
      file.flush  # Force write to disk
    end
  rescue Errno::EACCES => e
    raise IOError, "Permission denied writing backup file #{file_path}: #{e.message}"
  rescue Errno::ENOSPC => e
    raise IOError, "No space left on device for backup file #{file_path}: #{e.message}"
  rescue Errno::EIO => e
    raise IOError, "I/O error writing backup file #{file_path}: #{e.message}"
  rescue SystemCallError => e
    raise IOError, "System error writing backup file #{file_path}: #{e.message}"
  end

  def verify_file_created(file_path)
    unless File.exist?(file_path)
      raise StandardError, "Backup file was not created: #{file_path}"
    end
    
    file_size = File.size(file_path)
    if file_size == 0
      raise StandardError, "Backup file is empty: #{file_path}"
    end
    
    @logger.debug("Verified backup file: #{file_path} (#{file_size} bytes)")
    file_size
  rescue Errno::EACCES => e
    raise IOError, "Permission denied accessing backup file #{file_path}: #{e.message}"
  rescue SystemCallError => e
    raise IOError, "System error accessing backup file #{file_path}: #{e.message}"
  end

  def move_file(source, destination)
    File.rename(source, destination)
    @logger.debug("Moved file from #{source} to #{destination}")
  rescue Errno::EACCES => e
    raise IOError, "Permission denied moving file to #{destination}: #{e.message}"
  rescue Errno::ENOSPC => e
    raise IOError, "No space left on device for file #{destination}: #{e.message}"
  rescue Errno::EXDEV => e
    # Cross-device link error, try copy instead
    begin
      FileUtils.cp(source, destination)
      File.delete(source)
      @logger.debug("Copied file from #{source} to #{destination} (cross-device)")
    rescue => copy_error
      raise IOError, "Failed to copy file to #{destination}: #{copy_error.message}"
    end
  rescue SystemCallError => e
    raise IOError, "System error moving file to #{destination}: #{e.message}"
  end

  def compress_file(source_file, target_file)
    File.open(target_file, 'wb') do |gz_file|
      gz = Zlib::GzipWriter.new(gz_file)
      begin
        File.open(source_file, 'rb') do |input_file|
          gz.write(input_file.read)
        end
      ensure
        gz.close
      end
    end
    
    # Remove the uncompressed source file
    File.delete(source_file) if File.exist?(source_file)
    @logger.debug("Compressed file: #{target_file}")
  rescue Errno::EACCES => e
    raise IOError, "Permission denied compressing file #{target_file}: #{e.message}"
  rescue Errno::ENOSPC => e
    raise IOError, "No space left on device for compressed file #{target_file}: #{e.message}"
  rescue Zlib::Error => e
    raise StandardError, "Compression failed for file #{target_file}: #{e.message}"
  rescue SystemCallError => e
    raise IOError, "System error compressing file #{target_file}: #{e.message}"
  end

  def calculate_checksum(file_path)
    Digest::SHA256.file(file_path).hexdigest
  end

  def verify_file_integrity(file_path, minimum_size = 10)
    file_size = File.size(file_path)
    is_compressed = file_path.end_with?('.gz')
    
    # Check minimum file size (empty backups are suspicious)
    min_size = is_compressed ? 20 : minimum_size  # Compressed files have overhead
    if file_size < min_size
      raise StandardError, "Backup file is too small (#{file_size} bytes), likely corrupted or empty"
    end
    
    # Calculate checksum for integrity tracking
    checksum = calculate_checksum(file_path)
    compression_info = is_compressed ? " (compressed)" : ""
    @logger.info("File verification: size=#{file_size} bytes#{compression_info}, sha256=#{checksum}")
    
    { size: file_size, checksum: checksum, compressed: is_compressed }
  end

  def cleanup_files(file_paths)
    file_paths.each do |file_path|
      next unless File.exist?(file_path)
      
      begin
        File.delete(file_path)
        @logger.debug("Cleaned up file: #{file_path}")
      rescue Errno::EACCES => e
        @logger.warn("Permission denied cleaning up file #{file_path}: #{e.message}")
      rescue SystemCallError => e
        @logger.warn("System error cleaning up file #{file_path}: #{e.message}")
      end
    end
  end

  def store_metadata(file_path, metadata)
    metadata_file = "#{file_path}.meta"
    File.write(metadata_file, metadata.to_json)
    @logger.debug("Stored metadata: #{metadata_file}")
  rescue => e
    @logger.warn("Failed to store metadata for #{file_path}: #{e.message}")
  end

  private

  def get_available_disk_space(path)
    # Get filesystem statistics using portable approach
    if defined?(File::Stat) && File::Stat.method_defined?(:statvfs)
      stat = File.statvfs(path)
      # Available space = block size * available blocks
      stat.bavail * stat.frsize
    else
      # Fallback: use df command for cross-platform compatibility
      df_output = `df -k #{path} 2>/dev/null | tail -1`
      if $?.success? && df_output.match(/\s+(\d+)\s+\d+%?\s*$/)
        # Convert from 1K blocks to bytes
        $1.to_i * 1024
      else
        @logger.warn("Could not determine disk space for #{path} using df command")
        # Return a large number to avoid blocking on disk space check failure
        1024 * 1024 * 1024  # 1GB
      end
    end
  rescue SystemCallError => e
    @logger.warn("Could not determine disk space for #{path}: #{e.message}")
    # Return a large number to avoid blocking on disk space check failure
    1024 * 1024 * 1024  # 1GB
  end
end