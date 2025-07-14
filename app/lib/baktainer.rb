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

STDOUT.sync = true


class Baktainer::Runner
  def initialize(url: 'unix:///var/run/docker.sock', ssl: false, ssl_options: {}, threads: 5)
    @pool = Concurrent::FixedThreadPool.new(threads)
    @url = url
    @ssl = ssl
    @ssl_options = ssl_options
    Docker.url = @url
    setup_ssl
    log_level_str = ENV['LOG_LEVEL'] || 'info'
    LOGGER.level = case log_level_str.downcase
                   when 'debug' then Logger::DEBUG
                   when 'info' then Logger::INFO
                   when 'warn' then Logger::WARN
                   when 'error' then Logger::ERROR
                   else Logger::INFO
                   end
  end

  def perform_backup
    LOGGER.info('Starting backup process.')
    LOGGER.debug('Docker Searching for containers.')
    Baktainer::Containers.find_all.each do |container|
      @pool.post do
        begin
          LOGGER.info("Backing up container #{container.name} with engine #{container.engine}.")
          container.backup
          LOGGER.info("Backup completed for container #{container.name}.")
        rescue StandardError => e
          LOGGER.error("Error backing up container #{container.name}: #{e.message}")
          LOGGER.debug(e.backtrace.join("\n"))
        end
      end
    end
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
      LOGGER.info("Sleeping for #{sleep_duration} seconds until #{next_run}.")
      sleep(sleep_duration)
      perform_backup
    end
  end

  private

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
      
      LOGGER.info("SSL/TLS configuration completed successfully")
    rescue => e
      LOGGER.error("Failed to configure SSL/TLS: #{e.message}")
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
      LOGGER.debug("Loaded CA certificate from file: #{ENV['BT_CA']}")
    else
      LOGGER.debug("Using CA certificate data from environment variable")
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
      LOGGER.debug("Loaded client certificate from file: #{ENV['BT_CERT']}")
    end
    
    if File.exist?(key_data)
      key_data = File.read(key_data)
      LOGGER.debug("Loaded client key from file: #{ENV['BT_KEY']}")
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
end
