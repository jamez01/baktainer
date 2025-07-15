# frozen_string_literal: true

# The `Container` class represents a container abstraction within the Baktainer application.
# It is responsible for encapsulating the logic and behavior related to managing containers.
# This class serves as a core component of the application, providing methods and attributes
# to interact with and manipulate container instances.

require 'fileutils'
require 'date'
require 'baktainer/container_validator'
require 'baktainer/backup_orchestrator'
require 'baktainer/file_system_operations'
require 'baktainer/dependency_container'

class Baktainer::Container
  def initialize(container, dependency_container = nil)
    @container = container
    @backup_command = Baktainer::BackupCommand.new
    @dependency_container = dependency_container || Baktainer::DependencyContainer.new.configure
    @logger = @dependency_container.get(:logger)
    @file_system_ops = @dependency_container.get(:file_system_operations)
  end

  def id
    @container.id
  end

  def labels
    @container.info['Labels']
  end

  def name
    container_name = @container.info['Names']&.first
    container_name&.start_with?('/') ? container_name[1..-1] : container_name
  end

  def backup_name
    labels['baktainer.name'] || name
  end

  def state
    @container.info['State']&.[]('Status')
  end

  def running?
    state == 'running'
  end

  def engine
    labels['baktainer.db.engine']&.downcase
  end

  def login
    labels['baktainer.db.user'] || nil
  end

  def user
    login
  end

  def password
    labels['baktainer.db.password'] || nil
  end

  def database
    labels['baktainer.db.name'] || nil
  end

  def all_databases?
    labels['baktainer.db.all'] == 'true'
  end

  
  def validate
    validator = Baktainer::ContainerValidator.new(@container, @backup_command)
    validator.validate!
    true
  rescue Baktainer::ValidationError => e
    raise e.message
  end

  def backup
    @logger.debug("Starting backup for container #{backup_name} with engine #{engine}.")
    return unless validate
    @logger.debug("Container #{backup_name} is valid for backup.")
    
    # Create metadata for the backup orchestrator
    metadata = {
      name: backup_name,
      engine: engine,
      database: database,
      user: user,
      password: password,
      all: all_databases?
    }
    
    orchestrator = @dependency_container.get(:backup_orchestrator)
    orchestrator.perform_backup(@container, metadata)
  end

  def docker_container
    @container
  end

  private

  # Delegated to BackupOrchestrator

  def should_compress_backup?
    # Check container-specific label first
    container_compress = labels['baktainer.compress']
    if container_compress
      return container_compress.downcase == 'true'
    end
    
    # Fall back to global environment variable (default: true)
    global_compress = ENV['BT_COMPRESS']
    if global_compress
      return global_compress.downcase == 'true'
    end
    
    # Default to true if no setting specified
    true
  end

  # Delegated to BackupOrchestrator and FileSystemOperations

  def backup_command
    if @backup_command.respond_to?(engine.to_sym)
      return @backup_command.send(engine.to_sym, login: login, password: password, database: database)
    elsif engine == 'custom'
      return @backup_command.custom(command: labels['baktainer.command']) || raise('Custom command not defined. Set docker label bt_command.')
    else
      raise "Unknown engine: #{engine}"
    end
  end
end

# :NODOC:
class Baktainer::Containers
  def self.find_all(dependency_container = nil)
    dep_container = dependency_container || Baktainer::DependencyContainer.new.configure
    logger = dep_container.get(:logger)
    
    logger.debug('Searching for containers with backup labels.')
    
    begin
      containers = Docker::Container.all.select do |container|
        begin
          labels = container.info['Labels']
          labels && labels['baktainer.backup'] == 'true'
        rescue Docker::Error::DockerError => e
          logger.warn("Failed to get info for container: #{e.message}")
          false
        end
      end
      
      logger.debug("Found #{containers.size} containers with backup labels.")
      logger.debug(containers.first.class) if containers.any?
      
      containers.map do |container|
        Baktainer::Container.new(container, dep_container)
      end
    rescue Docker::Error::TimeoutError => e
      logger.error("Docker API timeout while searching containers: #{e.message}")
      raise StandardError, "Docker API timeout: #{e.message}"
    rescue Docker::Error::DockerError => e
      logger.error("Docker API error while searching containers: #{e.message}")
      raise StandardError, "Docker API error: #{e.message}"
    rescue StandardError => e
      logger.error("System error while searching containers: #{e.message}")
      raise StandardError, "Container search failed: #{e.message}"
    end
  end
end
