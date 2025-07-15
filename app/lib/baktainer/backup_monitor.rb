# frozen_string_literal: true

require 'json'
require 'concurrent'

# Monitors backup operations and tracks performance metrics
class Baktainer::BackupMonitor
  attr_reader :metrics, :alerts

  def initialize(logger, notification_system = nil)
    @logger = logger
    @notification_system = notification_system
    @metrics = Concurrent::Hash.new
    @alerts = Concurrent::Array.new
    @start_times = Concurrent::Hash.new
    @backup_history = Concurrent::Array.new
    @mutex = Mutex.new
  end

  def start_backup(container_name, engine)
    @start_times[container_name] = Time.now
    @logger.debug("Started monitoring backup for #{container_name} (#{engine})")
  end

  def complete_backup(container_name, file_path, file_size = nil)
    start_time = @start_times.delete(container_name)
    return unless start_time

    duration = Time.now - start_time
    actual_file_size = file_size || (File.exist?(file_path) ? File.size(file_path) : 0)
    
    backup_record = {
      container_name: container_name,
      timestamp: Time.now.iso8601,
      duration: duration,
      file_size: actual_file_size,
      file_path: file_path,
      status: 'success'
    }
    
    record_backup_metrics(backup_record)
    @logger.info("Backup completed for #{container_name} in #{duration.round(2)}s (#{format_file_size(actual_file_size)})")
    
    # Send notification if system is available
    if @notification_system
      @notification_system.notify_backup_completed(container_name, file_path, actual_file_size, duration)
    end
  end

  def fail_backup(container_name, error_message)
    start_time = @start_times.delete(container_name)
    duration = start_time ? Time.now - start_time : 0
    
    backup_record = {
      container_name: container_name,
      timestamp: Time.now.iso8601,
      duration: duration,
      file_size: 0,
      file_path: nil,
      status: 'failed',
      error: error_message
    }
    
    record_backup_metrics(backup_record)
    check_failure_alerts(container_name, error_message)
    @logger.error("Backup failed for #{container_name} after #{duration.round(2)}s: #{error_message}")
    
    # Send notification if system is available
    if @notification_system
      @notification_system.notify_backup_failed(container_name, error_message, duration)
    end
  end

  def get_metrics_summary
    @mutex.synchronize do
      recent_backups = @backup_history.last(100)
      successful_backups = recent_backups.select { |b| b[:status] == 'success' }
      failed_backups = recent_backups.select { |b| b[:status] == 'failed' }
      
      {
        total_backups: recent_backups.size,
        successful_backups: successful_backups.size,
        failed_backups: failed_backups.size,
        success_rate: recent_backups.empty? ? 0 : (successful_backups.size.to_f / recent_backups.size * 100).round(2),
        average_duration: calculate_average_duration(successful_backups),
        average_file_size: calculate_average_file_size(successful_backups),
        total_data_backed_up: successful_backups.sum { |b| b[:file_size] },
        active_alerts: @alerts.size,
        last_updated: Time.now.iso8601
      }
    end
  end

  def get_container_metrics(container_name)
    @mutex.synchronize do
      container_backups = @backup_history.select { |b| b[:container_name] == container_name }
      successful_backups = container_backups.select { |b| b[:status] == 'success' }
      failed_backups = container_backups.select { |b| b[:status] == 'failed' }
      
      return nil if container_backups.empty?
      
      {
        container_name: container_name,
        total_backups: container_backups.size,
        successful_backups: successful_backups.size,
        failed_backups: failed_backups.size,
        success_rate: (successful_backups.size.to_f / container_backups.size * 100).round(2),
        average_duration: calculate_average_duration(successful_backups),
        average_file_size: calculate_average_file_size(successful_backups),
        last_backup: container_backups.last[:timestamp],
        last_backup_status: container_backups.last[:status]
      }
    end
  end

  def get_performance_alerts
    @alerts.to_a
  end

  def clear_alerts
    @alerts.clear
    @logger.info("Cleared all performance alerts")
  end

  # Get recent backups for health check endpoints
  def get_recent_backups(limit = 50)
    @mutex.synchronize do
      @backup_history.last(limit).reverse
    end
  end

  # Get failed backups for health check endpoints  
  def get_failed_backups(limit = 20)
    @mutex.synchronize do
      failed = @backup_history.select { |b| b[:status] == 'failed' }
      failed.last(limit).reverse
    end
  end

  # Get backup history for a specific container
  def get_container_backup_history(container_name, limit = 20)
    @mutex.synchronize do
      container_backups = @backup_history.select { |b| b[:container_name] == container_name }
      container_backups.last(limit).reverse
    end
  end

  def export_metrics(format = :json)
    case format
    when :json
      {
        summary: get_metrics_summary,
        backup_history: @backup_history.last(50),
        alerts: @alerts.to_a
      }.to_json
    when :csv
      export_to_csv
    else
      raise ArgumentError, "Unsupported format: #{format}"
    end
  end

  private

  def record_backup_metrics(backup_record)
    @mutex.synchronize do
      @backup_history << backup_record
      
      # Keep only last 1000 records to prevent memory bloat
      @backup_history.shift if @backup_history.size > 1000
      
      # Check for performance issues
      check_performance_alerts(backup_record)
    end
  end

  def check_performance_alerts(backup_record)
    # Alert if backup took too long (> 10 minutes)
    if backup_record[:duration] > 600
      add_alert(:slow_backup, "Backup for #{backup_record[:container_name]} took #{backup_record[:duration].round(2)}s")
    end
    
    # Alert if backup file is suspiciously small (< 1KB)
    if backup_record[:status] == 'success' && backup_record[:file_size] < 1024
      add_alert(:small_backup, "Backup file for #{backup_record[:container_name]} is only #{backup_record[:file_size]} bytes")
    end
  end

  def check_failure_alerts(container_name, error_message)
    # Count recent failures for this container
    recent_failures = @backup_history.last(10).count do |backup|
      backup[:container_name] == container_name && backup[:status] == 'failed'
    end
    
    if recent_failures >= 3
      add_alert(:repeated_failures, "Container #{container_name} has failed #{recent_failures} times recently")
    end
  end

  def add_alert(type, message)
    alert = {
      type: type,
      message: message,
      timestamp: Time.now.iso8601,
      id: SecureRandom.uuid
    }
    
    @alerts << alert
    @logger.warn("Performance alert: #{message}")
    
    # Keep only last 100 alerts
    @alerts.shift if @alerts.size > 100
  end

  def calculate_average_duration(backups)
    return 0 if backups.empty?
    (backups.sum { |b| b[:duration] } / backups.size).round(2)
  end

  def calculate_average_file_size(backups)
    return 0 if backups.empty?
    (backups.sum { |b| b[:file_size] } / backups.size).round(0)
  end

  def format_file_size(size)
    units = ['B', 'KB', 'MB', 'GB', 'TB']
    unit_index = 0
    size_float = size.to_f
    
    while size_float >= 1024 && unit_index < units.length - 1
      size_float /= 1024
      unit_index += 1
    end
    
    "#{size_float.round(2)} #{units[unit_index]}"
  end

  def export_to_csv
    require 'csv'
    
    CSV.generate(headers: true) do |csv|
      csv << ['Container', 'Timestamp', 'Duration', 'File Size', 'Status', 'Error']
      
      @backup_history.each do |backup|
        csv << [
          backup[:container_name],
          backup[:timestamp],
          backup[:duration],
          backup[:file_size],
          backup[:status],
          backup[:error]
        ]
      end
    end
  end
end