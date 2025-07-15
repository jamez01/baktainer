# frozen_string_literal: true

# Baktainer is a class responsible for managing database backups using Docker containers.
#
# It supports the following database engines: PostgreSQL, MySQL, MariaDB, and Sqlite3.
#
# @example Initialize a Baktainer instance
#   baktainer = Baktainer.new(url: 'unix:///var/run/docker.sock', ssl: true, ssl_options: {})
#
# @example Run the backup process
#   baktainer.run
#
# @!attribute [r] SUPPORTED_ENGINES
#   @return [Array<String>] The list of supported database engines.
#
# @param url [String] The Docker API URL. Defaults to 'unix:///var/run/docker.sock'.
# @param ssl [Boolean] Whether to use SSL for Docker API communication. Defaults to false.
#
# @method perform_backup
#   Starts the backup process by searching for Docker containers and performing backups.
#   Logs the process at various stages.
#
# @method run
#   Schedules and runs the backup process at a specified time.
#   If the time is invalid or not provided, defaults to 05:00.
#
# @private
# @method setup_ssl
#   Configures SSL settings for Docker API communication if SSL is enabled.
#   Uses environment variables `BT_CA`, `BT_CERT`, and `BT_KEY` for SSL certificates and keys.
module Baktainer
end

require 'docker-api'
require 'cron_calc'
require 'concurrent/executor/fixed_thread_pool'
require 'baktainer/logger'
require 'baktainer/container'
require 'baktainer/backup_command'
require 'baktainer/dependency_container'

STDOUT.sync = true


class Baktainer::Runner
  def initialize(url: 'unix:///var/run/docker.sock', ssl: false, ssl_options: {}, threads: 5)
    @dependency_container = Baktainer::DependencyContainer.new.configure
    @logger = @dependency_container.get(:logger)
    @pool = @dependency_container.get(:thread_pool)
    @backup_monitor = @dependency_container.get(:backup_monitor)
    @backup_rotation = @dependency_container.get(:backup_rotation)
    @url = url
    @ssl = ssl
    @ssl_options = ssl_options
    Docker.url = @url
    
    # Initialize Docker client through dependency container if SSL is enabled
    if @ssl
      @dependency_container.get(:docker_client)
    end
    
    # Start health check server if enabled
    start_health_server if ENV['BT_HEALTH_SERVER_ENABLED'] == 'true'
  end

  def perform_backup
    @logger.info('Starting backup process.')
    
    # Perform health check before backup
    unless docker_health_check
      @logger.error('Docker connection health check failed. Aborting backup.')
      return { successful: [], failed: [], total: 0, error: 'Docker connection failed' }
    end
    
    @logger.debug('Docker Searching for containers.')
    
    containers = Baktainer::Containers.find_all(@dependency_container)
    backup_futures = []
    backup_results = {
      successful: [],
      failed: [],
      total: containers.size
    }
    
    containers.each do |container|
      future = @pool.post do
        begin
          @logger.info("Backing up container #{container.name} with engine #{container.engine}.")
          @backup_monitor.start_backup(container.name, container.engine)
          
          backup_path = container.backup
          
          @backup_monitor.complete_backup(container.name, backup_path)
          @logger.info("Backup completed for container #{container.name}.")
          { container: container.name, status: :success, path: backup_path }
        rescue StandardError => e
          @backup_monitor.fail_backup(container.name, e.message)
          @logger.error("Error backing up container #{container.name}: #{e.message}")
          @logger.debug(e.backtrace.join("\n"))
          { container: container.name, status: :failed, error: e.message }
        end
      end
      backup_futures << future
    end
    
    # Wait for all backups to complete and collect results
    backup_futures.each do |future|
      begin
        result = future.value  # This will block until the future completes
        if result[:status] == :success
          backup_results[:successful] << result
        else
          backup_results[:failed] << result
        end
      rescue StandardError => e
        @logger.error("Thread pool error: #{e.message}")
        backup_results[:failed] << { container: 'unknown', status: :failed, error: e.message }
      end
    end
    
    # Log summary and metrics
    @logger.info("Backup process completed. Success: #{backup_results[:successful].size}, Failed: #{backup_results[:failed].size}, Total: #{backup_results[:total]}")
    
    # Log metrics summary
    metrics = @backup_monitor.get_metrics_summary
    @logger.info("Overall metrics: success_rate=#{metrics[:success_rate]}%, total_data=#{format_bytes(metrics[:total_data_backed_up])}")
    
    # Log failed backups for monitoring
    backup_results[:failed].each do |failure|
      @logger.error("Failed backup for #{failure[:container]}: #{failure[:error]}")
    end
    
    # Run backup rotation/cleanup if enabled
    if ENV['BT_ROTATION_ENABLED'] != 'false'
      @logger.info('Running backup rotation and cleanup')
      cleanup_results = @backup_rotation.cleanup
      if cleanup_results[:deleted_count] > 0
        @logger.info("Cleaned up #{cleanup_results[:deleted_count]} old backups, freed #{format_bytes(cleanup_results[:deleted_size])}")
      end
    end
    
    backup_results
  end

  def run
    run_at = ENV['BT_CRON'] || '0 0 * * *'
    begin
      @cron = CronCalc.new(run_at)
    rescue 
      LOGGER.error("Invalid cron format for BT_CRON: #{run_at}.")
      @cron = CronCalc.new('0 0 * * *') # Fall back to default
    end

    loop do
      now = Time.now
      next_run = @cron.next
      sleep_duration = next_run - now
      @logger.info("Sleeping for #{sleep_duration} seconds until #{next_run}.")
      sleep(sleep_duration)
      perform_backup
    end
  end

  private

  def format_bytes(bytes)
    units = ['B', 'KB', 'MB', 'GB']
    unit_index = 0
    size = bytes.to_f
    
    while size >= 1024 && unit_index < units.length - 1
      size /= 1024
      unit_index += 1
    end
    
    "#{size.round(2)} #{units[unit_index]}"
  end

  def setup_ssl
    return unless @ssl

    begin
      # Validate required SSL environment variables
      validate_ssl_environment
      
      # Load and validate CA certificate
      ca_cert = load_ca_certificate
      
      # Load and validate client certificates
      client_cert, client_key = load_client_certificates
      
      # Create certificate store and add CA
      @cert_store = OpenSSL::X509::Store.new
      @cert_store.add_cert(ca_cert)
      
      # Configure Docker SSL options
      Docker.options = {
        client_cert_data: client_cert,
        client_key_data: client_key,
        ssl_cert_store: @cert_store,
        ssl_verify_peer: true,
        scheme: 'https'
      }
      
      @logger.info("SSL/TLS configuration completed successfully")
    rescue => e
      @logger.error("Failed to configure SSL/TLS: #{e.message}")
      raise SecurityError, "SSL/TLS configuration failed: #{e.message}"
    end
  end

  def validate_ssl_environment
    missing_vars = []
    missing_vars << 'BT_CA' unless ENV['BT_CA']
    missing_vars << 'BT_CERT' unless ENV['BT_CERT']
    missing_vars << 'BT_KEY' unless ENV['BT_KEY']
    
    unless missing_vars.empty?
      raise ArgumentError, "Missing required SSL environment variables: #{missing_vars.join(', ')}"
    end
  end

  def load_ca_certificate
    ca_data = ENV['BT_CA']
    
    # Support both file paths and direct certificate data
    if File.exist?(ca_data)
      ca_data = File.read(ca_data)
      @logger.debug("Loaded CA certificate from file: #{ENV['BT_CA']}")
    else
      @logger.debug("Using CA certificate data from environment variable")
    end
    
    OpenSSL::X509::Certificate.new(ca_data)
  rescue OpenSSL::X509::CertificateError => e
    raise SecurityError, "Invalid CA certificate: #{e.message}"
  rescue Errno::ENOENT
    raise SecurityError, "CA certificate file not found: #{ENV['BT_CA']}"
  rescue => e
    raise SecurityError, "Failed to load CA certificate: #{e.message}"
  end

  def load_client_certificates
    cert_data = ENV['BT_CERT']
    key_data = ENV['BT_KEY']
    
    # Support both file paths and direct certificate data
    if File.exist?(cert_data)
      cert_data = File.read(cert_data)
      @logger.debug("Loaded client certificate from file: #{ENV['BT_CERT']}")
    end
    
    if File.exist?(key_data)
      key_data = File.read(key_data)
      @logger.debug("Loaded client key from file: #{ENV['BT_KEY']}")
    end
    
    # Validate certificate and key
    cert = OpenSSL::X509::Certificate.new(cert_data)
    key = OpenSSL::PKey::RSA.new(key_data)
    
    # Verify that the key matches the certificate
    unless cert.public_key.to_pem == key.public_key.to_pem
      raise SecurityError, "Client certificate and key do not match"
    end
    
    # Check certificate validity
    now = Time.now
    if cert.not_before > now
      raise SecurityError, "Client certificate is not yet valid (valid from: #{cert.not_before})"
    end
    
    if cert.not_after < now
      raise SecurityError, "Client certificate has expired (expired: #{cert.not_after})"
    end
    
    [cert_data, key_data]
  rescue OpenSSL::X509::CertificateError => e
    raise SecurityError, "Invalid client certificate: #{e.message}"
  rescue OpenSSL::PKey::RSAError => e
    raise SecurityError, "Invalid client key: #{e.message}"
  rescue Errno::ENOENT => e
    raise SecurityError, "Certificate file not found: #{e.message}"
  rescue => e
    raise SecurityError, "Failed to load client certificates: #{e.message}"
  end

  def verify_docker_connection
    begin
      @logger.debug("Verifying Docker connection to #{@url}")
      Docker.version
      @logger.info("Docker connection verified successfully")
    rescue Docker::Error::DockerError => e
      raise StandardError, "Docker connection failed: #{e.message}"
    rescue StandardError => e
      raise StandardError, "Docker connection error: #{e.message}"
    end
  end

  def docker_health_check
    begin
      # Check Docker daemon version
      version_info = Docker.version
      @logger.debug("Docker daemon version: #{version_info['Version']}")
      
      # Check if we can list containers
      Docker::Container.all(limit: 1)
      @logger.debug("Docker health check passed")
      
      true
    rescue Docker::Error::TimeoutError => e
      @logger.error("Docker health check failed - timeout: #{e.message}")
      false
    rescue Docker::Error::DockerError => e
      @logger.error("Docker health check failed - Docker error: #{e.message}")
      false
    rescue StandardError => e
      @logger.error("Docker health check failed - system error: #{e.message}")
      false
    end
  end

  def start_health_server
    @health_server_thread = Thread.new do
      begin
        health_server = @dependency_container.get(:health_check_server)
        port = ENV['BT_HEALTH_PORT'] || 8080
        bind = ENV['BT_HEALTH_BIND'] || '0.0.0.0'
        
        @logger.info("Starting health check server on #{bind}:#{port}")
        health_server.run!(host: bind, port: port.to_i)
      rescue => e
        @logger.error("Health check server error: #{e.message}")
      end
    end
    
    # Give the server a moment to start
    sleep 0.5
    @logger.info("Health check server started in background thread")
  end

  def stop_health_server
    if @health_server_thread
      @health_server_thread.kill
      @health_server_thread = nil
      @logger.info("Health check server stopped")
    end
  end
end
