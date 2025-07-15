# frozen_string_literal: true

require 'logger'
require 'docker'
require 'baktainer/configuration'
require 'baktainer/backup_monitor'
require 'baktainer/dynamic_thread_pool'
require 'baktainer/simple_thread_pool'
require 'baktainer/backup_rotation'
require 'baktainer/backup_encryption'
require 'baktainer/health_check_server'
require 'baktainer/notification_system'
require 'baktainer/label_validator'

# Dependency injection container for managing application dependencies
class Baktainer::DependencyContainer
  def initialize
    @factories = {}
    @instances = {}
    @singletons = {}
    @configuration = nil
    @logger = nil
  end

  # Register a service factory
  def register(name, &factory)
    @factories[name.to_sym] = factory
  end

  # Register a singleton service
  def singleton(name, &factory)
    @factories[name.to_sym] = factory
    @singletons[name.to_sym] = true
  end

  # Get a service instance
  def get(name)
    name = name.to_sym
    
    if @singletons[name]
      @instances[name] ||= create_service(name)
    else
      create_service(name)
    end
  end

  # Configure the container with standard services
  def configure
    # Configuration service (singleton)
    singleton(:configuration) do
      @configuration ||= Baktainer::Configuration.new
    end

    # Logger service (singleton)
    singleton(:logger) do
      @logger ||= create_logger
    end

    # Docker client service (singleton)
    singleton(:docker_client) do
      create_docker_client
    end

    # Backup monitor service (singleton)
    singleton(:backup_monitor) do
      Baktainer::BackupMonitor.new(get(:logger), get(:notification_system))
    end

    # Thread pool service (singleton)
    singleton(:thread_pool) do
      config = get(:configuration)
      # Create a simple thread pool implementation that works reliably
      SimpleThreadPool.new(config.threads)
    end

    # Backup orchestrator service
    register(:backup_orchestrator) do
      Baktainer::BackupOrchestrator.new(
        get(:logger),
        get(:configuration),
        get(:backup_encryption)
      )
    end

    # Container validator service - Note: Not used as dependency injection,
    # created directly in Container class due to parameter requirements

    # File system operations service
    register(:file_system_operations) do
      Baktainer::FileSystemOperations.new(get(:logger))
    end

    # Backup rotation service (singleton)
    singleton(:backup_rotation) do
      Baktainer::BackupRotation.new(get(:logger), get(:configuration))
    end

    # Backup encryption service (singleton)
    singleton(:backup_encryption) do
      Baktainer::BackupEncryption.new(get(:logger), get(:configuration))
    end

    # Notification system service (singleton)
    singleton(:notification_system) do
      Baktainer::NotificationSystem.new(get(:logger), get(:configuration))
    end

    # Label validator service (singleton)
    singleton(:label_validator) do
      Baktainer::LabelValidator.new(get(:logger))
    end

    # Health check server service (singleton)
    singleton(:health_check_server) do
      Baktainer::HealthCheckServer.new(self)
    end

    self
  end

  # Reset all services (useful for testing)
  def reset!
    @factories.clear
    @instances.clear
    @singletons.clear
    @configuration = nil
    @logger = nil
  end

  # Get all registered service names
  def registered_services
    @factories.keys
  end

  # Check if a service is registered
  def registered?(name)
    @factories.key?(name.to_sym)
  end

  # Override configuration for testing
  def override_configuration(config)
    @configuration = config
    @instances[:configuration] = config
  end

  # Override logger for testing
  def override_logger(logger)
    @logger = logger
    @instances[:logger] = logger
  end

  private

  def create_service(name)
    factory = @factories[name]
    raise ServiceNotFoundError, "Service '#{name}' not found" unless factory
    
    factory.call
  end

  def create_logger
    config = get(:configuration)
    
    logger = Logger.new(STDOUT)
    logger.level = case config.log_level.downcase
                   when 'debug' then Logger::DEBUG
                   when 'info' then Logger::INFO
                   when 'warn' then Logger::WARN
                   when 'error' then Logger::ERROR
                   else Logger::INFO
                   end
    
    # Set custom formatter for better output
    logger.formatter = proc do |severity, datetime, progname, msg|
      {
        severity: severity,
        timestamp: datetime.strftime('%Y-%m-%d %H:%M:%S %z'),
        progname: progname || 'backtainer',
        message: msg
      }.to_json + "\n"
    end
    
    logger
  end

  def create_docker_client
    config = get(:configuration)
    logger = get(:logger)
    
    Docker.url = config.docker_url
    
    if config.ssl_enabled?
      setup_ssl_connection(config, logger)
    end
    
    verify_docker_connection(logger)
    
    Docker
  end

  def setup_ssl_connection(config, logger)
    validate_ssl_environment(config)
    
    begin
      # Load and validate CA certificate
      ca_cert = load_ca_certificate(config)
      
      # Load and validate client certificates
      client_cert, client_key = load_client_certificates(config)
      
      # Create certificate store and add CA
      cert_store = OpenSSL::X509::Store.new
      cert_store.add_cert(ca_cert)
      
      # Configure Docker SSL options
      Docker.options = {
        ssl_ca_file: config.ssl_ca,
        ssl_cert_file: config.ssl_cert,
        ssl_key_file: config.ssl_key,
        ssl_verify_peer: true,
        ssl_cert_store: cert_store
      }
      
      logger.info("SSL/TLS configuration completed successfully")
    rescue => e
      logger.error("Failed to configure SSL/TLS: #{e.message}")
      raise SecurityError, "SSL/TLS configuration failed: #{e.message}"
    end
  end

  def validate_ssl_environment(config)
    missing_vars = []
    missing_vars << 'BT_CA' unless config.ssl_ca
    missing_vars << 'BT_CERT' unless config.ssl_cert
    missing_vars << 'BT_KEY' unless config.ssl_key
    
    unless missing_vars.empty?
      raise ArgumentError, "Missing required SSL environment variables: #{missing_vars.join(', ')}"
    end
  end

  def load_ca_certificate(config)
    ca_data = if File.exist?(config.ssl_ca)
      File.read(config.ssl_ca)
    else
      config.ssl_ca
    end
    
    OpenSSL::X509::Certificate.new(ca_data)
  rescue OpenSSL::X509::CertificateError => e
    raise SecurityError, "Invalid CA certificate: #{e.message}"
  rescue Errno::ENOENT => e
    raise SecurityError, "CA certificate file not found: #{config.ssl_ca}"
  rescue => e
    raise SecurityError, "Failed to load CA certificate: #{e.message}"
  end

  def load_client_certificates(config)
    cert_data = if File.exist?(config.ssl_cert)
      File.read(config.ssl_cert)
    else
      config.ssl_cert
    end
    
    key_data = if File.exist?(config.ssl_key)
      File.read(config.ssl_key)
    else
      config.ssl_key
    end
    
    cert = OpenSSL::X509::Certificate.new(cert_data)
    key = OpenSSL::PKey::RSA.new(key_data)
    
    # Verify that the key matches the certificate
    unless cert.check_private_key(key)
      raise SecurityError, "Client certificate and key do not match"
    end
    
    [cert, key]
  rescue OpenSSL::X509::CertificateError => e
    raise SecurityError, "Invalid client certificate: #{e.message}"
  rescue OpenSSL::PKey::RSAError => e
    raise SecurityError, "Invalid client key: #{e.message}"
  rescue Errno::ENOENT => e
    raise SecurityError, "Certificate file not found: #{e.message}"
  rescue => e
    raise SecurityError, "Failed to load client certificates: #{e.message}"
  end

  def verify_docker_connection(logger)
    begin
      logger.debug("Verifying Docker connection to #{Docker.url}")
      Docker.version
      logger.info("Docker connection verified successfully")
    rescue Docker::Error::DockerError => e
      raise StandardError, "Docker connection failed: #{e.message}"
    rescue StandardError => e
      raise StandardError, "Docker connection error: #{e.message}"
    end
  end
end

# Custom exception for service not found
class Baktainer::ServiceNotFoundError < StandardError; end