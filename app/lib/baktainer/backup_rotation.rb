# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'time'

# Manages backup rotation and cleanup based on retention policies
class Baktainer::BackupRotation
  attr_reader :retention_days, :retention_count, :min_free_space_gb

  def initialize(logger, configuration = nil)
    @logger = logger
    config = configuration || Baktainer::Configuration.new
    
    # Retention policies from environment or defaults
    @retention_days = (ENV['BT_RETENTION_DAYS'] || '30').to_i
    @retention_count = (ENV['BT_RETENTION_COUNT'] || '0').to_i  # 0 = unlimited
    @min_free_space_gb = (ENV['BT_MIN_FREE_SPACE_GB'] || '10').to_i
    @backup_dir = config.backup_dir
    
    @logger.info("Backup rotation initialized: days=#{@retention_days}, count=#{@retention_count}, min_space=#{@min_free_space_gb}GB")
  end

  # Run cleanup based on configured policies
  def cleanup(container_name = nil)
    @logger.info("Starting backup cleanup#{container_name ? " for #{container_name}" : ' for all containers'}")
    
    cleanup_results = {
      deleted_count: 0,
      deleted_size: 0,
      errors: []
    }
    
    begin
      # Apply retention policies only if configured
      if @retention_days > 0
        results = cleanup_by_age(container_name)
        cleanup_results[:deleted_count] += results[:deleted_count]
        cleanup_results[:deleted_size] += results[:deleted_size]
        cleanup_results[:errors].concat(results[:errors])
      end
      
      # Count-based cleanup runs on remaining files after age cleanup
      if @retention_count > 0
        results = cleanup_by_count(container_name)
        cleanup_results[:deleted_count] += results[:deleted_count]
        cleanup_results[:deleted_size] += results[:deleted_size]
        cleanup_results[:errors].concat(results[:errors])
      end
      
      # Check disk space and cleanup if needed
      if needs_space_cleanup?
        results = cleanup_for_space(container_name)
        cleanup_results[:deleted_count] += results[:deleted_count]
        cleanup_results[:deleted_size] += results[:deleted_size]
        cleanup_results[:errors].concat(results[:errors])
      end
      
      # Clean up empty date directories
      cleanup_empty_directories
      
      @logger.info("Cleanup completed: deleted #{cleanup_results[:deleted_count]} files, freed #{format_bytes(cleanup_results[:deleted_size])}")
      cleanup_results
    rescue => e
      @logger.error("Backup cleanup failed: #{e.message}")
      cleanup_results[:errors] << e.message
      cleanup_results
    end
  end

  # Get backup statistics
  def get_backup_statistics
    stats = {
      total_backups: 0,
      total_size: 0,
      containers: {},
      by_date: {},
      oldest_backup: nil,
      newest_backup: nil
    }
    
    Dir.glob(File.join(@backup_dir, '*')).each do |date_dir|
      next unless File.directory?(date_dir)
      date = File.basename(date_dir)
      
      Dir.glob(File.join(date_dir, '*.{sql,sql.gz}')).each do |backup_file|
        next unless File.file?(backup_file)
        
        file_info = parse_backup_filename(backup_file)
        next unless file_info
        
        container_name = file_info[:container_name]
        file_size = File.size(backup_file)
        file_time = File.mtime(backup_file)
        
        stats[:total_backups] += 1
        stats[:total_size] += file_size
        
        # Container statistics
        stats[:containers][container_name] ||= { count: 0, size: 0, oldest: nil, newest: nil }
        stats[:containers][container_name][:count] += 1
        stats[:containers][container_name][:size] += file_size
        
        # Update oldest/newest for container
        if stats[:containers][container_name][:oldest].nil? || file_time < stats[:containers][container_name][:oldest]
          stats[:containers][container_name][:oldest] = file_time
        end
        if stats[:containers][container_name][:newest].nil? || file_time > stats[:containers][container_name][:newest]
          stats[:containers][container_name][:newest] = file_time
        end
        
        # Date statistics
        stats[:by_date][date] ||= { count: 0, size: 0 }
        stats[:by_date][date][:count] += 1
        stats[:by_date][date][:size] += file_size
        
        # Overall oldest/newest
        stats[:oldest_backup] = file_time if stats[:oldest_backup].nil? || file_time < stats[:oldest_backup]
        stats[:newest_backup] = file_time if stats[:newest_backup].nil? || file_time > stats[:newest_backup]
      end
    end
    
    stats
  end

  private

  def cleanup_by_age(container_name = nil)
    @logger.debug("Cleaning up backups older than #{@retention_days} days")
    
    results = { deleted_count: 0, deleted_size: 0, errors: [] }
    cutoff_time = Time.now - (@retention_days * 24 * 60 * 60)
    
    each_backup_file(container_name) do |backup_file|
      begin
        if File.mtime(backup_file) < cutoff_time
          file_size = File.size(backup_file)
          delete_backup_file(backup_file)
          results[:deleted_count] += 1
          results[:deleted_size] += file_size
          @logger.debug("Deleted old backup: #{backup_file}")
        end
      rescue => e
        @logger.error("Failed to delete #{backup_file}: #{e.message}")
        results[:errors] << "Failed to delete #{backup_file}: #{e.message}"
      end
    end
    
    results
  end

  def cleanup_by_count(container_name = nil)
    @logger.debug("Keeping only #{@retention_count} most recent backups per container")
    
    results = { deleted_count: 0, deleted_size: 0, errors: [] }
    
    # Group backups by container
    backups_by_container = {}
    
    each_backup_file(container_name) do |backup_file|
      file_info = parse_backup_filename(backup_file)
      next unless file_info
      
      container = file_info[:container_name]
      backups_by_container[container] ||= []
      backups_by_container[container] << {
        path: backup_file,
        mtime: File.mtime(backup_file),
        size: File.size(backup_file)
      }
    end
    
    # Process each container
    backups_by_container.each do |container, backups|
      # Sort by modification time, newest first
      backups.sort_by! { |b| -b[:mtime].to_i }
      
      # Delete backups beyond retention count
      if backups.length > @retention_count
        backups[@retention_count..-1].each do |backup|
          begin
            delete_backup_file(backup[:path])
            results[:deleted_count] += 1
            results[:deleted_size] += backup[:size]
            @logger.debug("Deleted excess backup: #{backup[:path]}")
          rescue => e
            @logger.error("Failed to delete #{backup[:path]}: #{e.message}")
            results[:errors] << "Failed to delete #{backup[:path]}: #{e.message}"
          end
        end
      end
    end
    
    results
  end

  def cleanup_for_space(container_name = nil)
    @logger.info("Cleaning up backups to free disk space")
    
    results = { deleted_count: 0, deleted_size: 0, errors: [] }
    required_space = @min_free_space_gb * 1024 * 1024 * 1024
    
    # Get all backups sorted by age (oldest first)
    all_backups = []
    each_backup_file(container_name) do |backup_file|
      all_backups << {
        path: backup_file,
        mtime: File.mtime(backup_file),
        size: File.size(backup_file)
      }
    end
    
    all_backups.sort_by! { |b| b[:mtime] }
    
    # Delete oldest backups until we have enough space
    all_backups.each do |backup|
      break if get_free_space >= required_space
      
      begin
        delete_backup_file(backup[:path])
        results[:deleted_count] += 1
        results[:deleted_size] += backup[:size]
        @logger.info("Deleted backup for space: #{backup[:path]}")
      rescue => e
        @logger.error("Failed to delete #{backup[:path]}: #{e.message}")
        results[:errors] << "Failed to delete #{backup[:path]}: #{e.message}"
      end
    end
    
    results
  end

  def cleanup_empty_directories
    Dir.glob(File.join(@backup_dir, '*')).each do |date_dir|
      next unless File.directory?(date_dir)
      
      # Check if directory is empty (no backup files)
      if Dir.glob(File.join(date_dir, '*.{sql,sql.gz}')).empty?
        begin
          FileUtils.rmdir(date_dir)
          @logger.debug("Removed empty directory: #{date_dir}")
        rescue => e
          @logger.debug("Could not remove directory #{date_dir}: #{e.message}")
        end
      end
    end
  end

  def each_backup_file(container_name = nil)
    pattern = if container_name
      File.join(@backup_dir, '*', "#{container_name}-*.{sql,sql.gz}")
    else
      File.join(@backup_dir, '*', '*.{sql,sql.gz}')
    end
    
    Dir.glob(pattern).each do |backup_file|
      next unless File.file?(backup_file)
      yield backup_file
    end
  end

  def parse_backup_filename(filename)
    basename = File.basename(filename)
    # Match pattern: container-name-timestamp.sql or container-name-timestamp.sql.gz
    if match = basename.match(/^(.+)-(\d{10})\.(sql|sql\.gz)$/)
      {
        container_name: match[1],
        timestamp: Time.at(match[2].to_i),
        compressed: match[3] == 'sql.gz'
      }
    else
      nil
    end
  end

  def delete_backup_file(backup_file)
    # Delete the backup file
    File.delete(backup_file) if File.exist?(backup_file)
    
    # Delete associated metadata file if exists
    metadata_file = "#{backup_file}.meta"
    File.delete(metadata_file) if File.exist?(metadata_file)
  end

  def needs_space_cleanup?
    # Skip space cleanup if min_free_space_gb is 0 (disabled)
    return false if @min_free_space_gb == 0
    
    free_space = get_free_space
    required_space = @min_free_space_gb * 1024 * 1024 * 1024
    
    if free_space < required_space
      @logger.warn("Low disk space: #{format_bytes(free_space)} available, #{format_bytes(required_space)} required")
      true
    else
      false
    end
  end

  def get_free_space
    # Use df command for cross-platform compatibility
    df_output = `df -k #{@backup_dir} 2>/dev/null | tail -1`
    if $?.success? && df_output.match(/\s+(\d+)\s+\d+%?\s*$/)
      # Convert from 1K blocks to bytes
      $1.to_i * 1024
    else
      @logger.warn("Could not determine disk space for #{@backup_dir}")
      # Return a large number to avoid unnecessary cleanup
      1024 * 1024 * 1024 * 1024  # 1TB
    end
  rescue => e
    @logger.warn("Error checking disk space: #{e.message}")
    1024 * 1024 * 1024 * 1024  # 1TB
  end

  def format_bytes(bytes)
    units = ['B', 'KB', 'MB', 'GB', 'TB']
    unit_index = 0
    size = bytes.to_f
    
    while size >= 1024 && unit_index < units.length - 1
      size /= 1024
      unit_index += 1
    end
    
    "#{size.round(2)} #{units[unit_index]}"
  end
end