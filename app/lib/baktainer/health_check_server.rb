# frozen_string_literal: true

require 'sinatra/base'
require 'json'

# Health check HTTP server for monitoring Baktainer status
class Baktainer::HealthCheckServer < Sinatra::Base
  def initialize(dependency_container)
    super()
    @dependency_container = dependency_container
    @logger = @dependency_container.get(:logger)
    @backup_monitor = @dependency_container.get(:backup_monitor)
    @backup_rotation = @dependency_container.get(:backup_rotation)
    @started_at = Time.now
  end

  configure do
    set :environment, :production
    set :logging, false  # We'll handle logging ourselves
    set :port, ENV['BT_HEALTH_PORT'] || 8080
    set :bind, ENV['BT_HEALTH_BIND'] || '0.0.0.0'
  end

  # Basic health check endpoint
  get '/health' do
    content_type :json
    
    begin
      health_status = perform_health_check
      status_code = health_status[:status] == 'healthy' ? 200 : 503
      
      status status_code
      health_status.to_json
    rescue => e
      @logger.error("Health check error: #{e.message}")
      status 503
      {
        status: 'error',
        message: e.message,
        timestamp: Time.now.iso8601
      }.to_json
    end
  end

  # Detailed backup status endpoint
  get '/status' do
    content_type :json
    
    begin
      status_info = {
        service: 'baktainer',
        status: 'running',
        uptime_seconds: (Time.now - @started_at).to_i,
        started_at: @started_at.iso8601,
        docker_status: check_docker_status,
        backup_metrics: get_backup_metrics,
        backup_statistics: get_backup_statistics,
        system_info: get_system_info,
        timestamp: Time.now.iso8601
      }
      
      status_info.to_json
    rescue => e
      @logger.error("Status endpoint error: #{e.message}")
      status 500
      {
        status: 'error',
        message: e.message,
        timestamp: Time.now.iso8601
      }.to_json
    end
  end

  # Backup history endpoint
  get '/backups' do
    content_type :json
    
    begin
      backup_info = {
        recent_backups: @backup_monitor.get_recent_backups(50),
        failed_backups: @backup_monitor.get_failed_backups(20),
        metrics_summary: @backup_monitor.get_metrics_summary,
        timestamp: Time.now.iso8601
      }
      
      backup_info.to_json
    rescue => e
      @logger.error("Backups endpoint error: #{e.message}")
      status 500
      {
        status: 'error',
        message: e.message,
        timestamp: Time.now.iso8601
      }.to_json
    end
  end

  # Container discovery endpoint
  get '/containers' do
    content_type :json
    
    begin
      containers = Baktainer::Containers.find_all(@dependency_container)
      container_info = containers.map do |container|
        {
          name: container.name,
          engine: container.engine,
          database: container.database,
          user: container.user,
          all_databases: container.all_databases?,
          container_id: container.docker_container.id,
          created: container.docker_container.info['Created'],
          state: container.docker_container.info['State']
        }
      end
      
      {
        total_containers: container_info.size,
        containers: container_info,
        timestamp: Time.now.iso8601
      }.to_json
    rescue => e
      @logger.error("Containers endpoint error: #{e.message}")
      status 500
      {
        status: 'error',
        message: e.message,
        timestamp: Time.now.iso8601
      }.to_json
    end
  end

  # Configuration endpoint (sanitized for security)
  get '/config' do
    content_type :json
    
    begin
      config = @dependency_container.get(:configuration)
      sanitized_config = {
        docker_url: config.docker_url.gsub(/\/\/.*@/, '//***@'), # Hide credentials
        backup_dir: config.backup_dir,
        log_level: config.log_level,
        threads: config.threads,
        ssl_enabled: config.ssl_enabled?,
        cron_schedule: ENV['BT_CRON'] || '0 0 * * *',
        rotation_enabled: ENV['BT_ROTATION_ENABLED'] != 'false',
        encryption_enabled: ENV['BT_ENCRYPTION_ENABLED'] == 'true',
        timestamp: Time.now.iso8601
      }
      
      sanitized_config.to_json
    rescue => e
      @logger.error("Config endpoint error: #{e.message}")
      status 500
      {
        status: 'error',
        message: e.message,
        timestamp: Time.now.iso8601
      }.to_json
    end
  end

  # Metrics endpoint for monitoring systems
  get '/metrics' do
    content_type 'text/plain'
    
    begin
      metrics = generate_prometheus_metrics
      metrics
    rescue => e
      @logger.error("Metrics endpoint error: #{e.message}")
      status 500
      "# Error generating metrics: #{e.message}\n"
    end
  end

  # Dashboard endpoint
  get '/' do
    content_type 'text/html'
    
    begin
      dashboard_path = File.join(File.dirname(__FILE__), 'dashboard.html')
      File.read(dashboard_path)
    rescue => e
      @logger.error("Dashboard endpoint error: #{e.message}")
      status 500
      "<html><body><h1>Error</h1><p>Failed to load dashboard: #{e.message}</p></body></html>"
    end
  end

  private

  def perform_health_check
    health_data = {
      status: 'healthy',
      checks: {},
      timestamp: Time.now.iso8601
    }

    # Check Docker connectivity
    begin
      Docker.version
      health_data[:checks][:docker] = { status: 'healthy', message: 'Connected' }
    rescue => e
      health_data[:status] = 'unhealthy'
      health_data[:checks][:docker] = { status: 'unhealthy', message: e.message }
    end

    # Check backup directory accessibility
    begin
      config = @dependency_container.get(:configuration)
      if File.writable?(config.backup_dir)
        health_data[:checks][:backup_directory] = { status: 'healthy', message: 'Writable' }
      else
        health_data[:status] = 'degraded'
        health_data[:checks][:backup_directory] = { status: 'warning', message: 'Not writable' }
      end
    rescue => e
      health_data[:status] = 'unhealthy'
      health_data[:checks][:backup_directory] = { status: 'unhealthy', message: e.message }
    end

    # Check recent backup status
    begin
      metrics = @backup_monitor.get_metrics_summary
      if metrics[:success_rate] >= 90
        health_data[:checks][:backup_success_rate] = { status: 'healthy', message: "#{metrics[:success_rate]}%" }
      elsif metrics[:success_rate] >= 50
        health_data[:status] = 'degraded' if health_data[:status] == 'healthy'
        health_data[:checks][:backup_success_rate] = { status: 'warning', message: "#{metrics[:success_rate]}%" }
      else
        health_data[:status] = 'unhealthy'
        health_data[:checks][:backup_success_rate] = { status: 'unhealthy', message: "#{metrics[:success_rate]}%" }
      end
    rescue => e
      health_data[:checks][:backup_success_rate] = { status: 'unknown', message: e.message }
    end

    health_data
  end

  def check_docker_status
    {
      version: Docker.version,
      containers_total: Docker::Container.all.size,
      containers_running: Docker::Container.all(filters: { status: ['running'] }).size,
      backup_containers: Baktainer::Containers.find_all(@dependency_container).size
    }
  rescue => e
    { error: e.message }
  end

  def get_backup_metrics
    @backup_monitor.get_metrics_summary
  rescue => e
    { error: e.message }
  end

  def get_backup_statistics
    @backup_rotation.get_backup_statistics
  rescue => e
    { error: e.message }
  end

  def get_system_info
    {
      ruby_version: RUBY_VERSION,
      platform: RUBY_PLATFORM,
      pid: Process.pid,
      memory_usage_mb: get_memory_usage,
      load_average: get_load_average
    }
  end

  def get_memory_usage
    # Get RSS memory usage in MB (Linux/Unix)
    if File.exist?('/proc/self/status')
      status = File.read('/proc/self/status')
      if match = status.match(/VmRSS:\s+(\d+)\s+kB/)
        return match[1].to_i / 1024  # Convert KB to MB
      end
    end
    nil
  rescue
    nil
  end

  def get_load_average
    if File.exist?('/proc/loadavg')
      loadavg = File.read('/proc/loadavg').strip.split
      return {
        one_minute: loadavg[0].to_f,
        five_minutes: loadavg[1].to_f,
        fifteen_minutes: loadavg[2].to_f
      }
    end
    nil
  rescue
    nil
  end

  def generate_prometheus_metrics
    metrics = []
    
    # Basic metrics
    metrics << "# HELP baktainer_uptime_seconds Total uptime in seconds"
    metrics << "# TYPE baktainer_uptime_seconds counter"
    metrics << "baktainer_uptime_seconds #{(Time.now - @started_at).to_i}"
    
    # Backup metrics
    begin
      backup_metrics = @backup_monitor.get_metrics_summary
      
      metrics << "# HELP baktainer_backups_total Total number of backup attempts"
      metrics << "# TYPE baktainer_backups_total counter"
      metrics << "baktainer_backups_total #{backup_metrics[:total_attempts]}"
      
      metrics << "# HELP baktainer_backups_successful Total number of successful backups"
      metrics << "# TYPE baktainer_backups_successful counter"
      metrics << "baktainer_backups_successful #{backup_metrics[:successful_backups]}"
      
      metrics << "# HELP baktainer_backups_failed Total number of failed backups"
      metrics << "# TYPE baktainer_backups_failed counter"
      metrics << "baktainer_backups_failed #{backup_metrics[:failed_backups]}"
      
      metrics << "# HELP baktainer_backup_success_rate_percent Success rate percentage"
      metrics << "# TYPE baktainer_backup_success_rate_percent gauge"
      metrics << "baktainer_backup_success_rate_percent #{backup_metrics[:success_rate]}"
      
      metrics << "# HELP baktainer_backup_data_bytes Total data backed up in bytes"
      metrics << "# TYPE baktainer_backup_data_bytes counter"
      metrics << "baktainer_backup_data_bytes #{backup_metrics[:total_data_backed_up]}"
    rescue => e
      metrics << "# Error getting backup metrics: #{e.message}"
    end
    
    # Container metrics
    begin
      containers = Baktainer::Containers.find_all(@dependency_container)
      metrics << "# HELP baktainer_containers_discovered Number of containers with backup labels"
      metrics << "# TYPE baktainer_containers_discovered gauge"
      metrics << "baktainer_containers_discovered #{containers.size}"
    rescue => e
      metrics << "# Error getting container metrics: #{e.message}"
    end
    
    metrics.join("\n") + "\n"
  end
end