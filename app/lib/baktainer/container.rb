# frozen_string_literal: true

# The `Container` class represents a container abstraction within the Baktainer application.
# It is responsible for encapsulating the logic and behavior related to managing containers.
# This class serves as a core component of the application, providing methods and attributes
# to interact with and manipulate container instances.

require 'fileutils'
require 'date'

class Baktainer::Container
  def initialize(container)
    @container = container
    @backup_command = Baktainer::BackupCommand.new
  end

  def id
    @container.id
  end

  def labels
    @container.info['Labels']
  end

  def name
    labels["baktainer.name"] || @container.info['Names'].first
  end

  def state
    @container.info['State']
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

  def password
    labels['baktainer.db.password'] || nil
  end

  def database
    labels['baktainer.db.name'] || nil
  end

  def validdate
    return raise 'Unable to parse container' if @container.nil?
    return raise 'Container not running' if state.nil? || state != 'running'
    return raise 'Use docker labels to define db settings' if labels.nil? || labels.empty?
    if labels['baktainer.backup']&.downcase != 'true'
      return raise 'Backup not enabled for this container. Set docker label baktainer.backup=true'
    end
    LOGGER.debug("Container labels['baktainer.db.engine']: #{labels['baktainer.db.engine']}")
    if engine.nil? || !@backup_command.respond_to?(engine.to_sym)
      return raise 'DB Engine not defined. Set docker label baktainer.engine.'
    end

    true
  end

  def backup
    LOGGER.debug("Starting backup for container #{name} with engine #{engine}.")
    return unless validdate
    LOGGER.debug("Container #{name} is valid for backup.")
    backup_dir = "/backups/#{Date.today}"
    FileUtils.mkdir_p("/backups/#{Date.today}") unless Dir.exist?(backup_dir)
    sql_dump = File.open("/backups/#{Date.today}/#{name}-#{Time.now.to_i}.sql", 'w')
    command = backup_command
    LOGGER.debug("Backup command environment variables: #{command[:env].inspect}")
    @container.exec(command[:cmd], env: command[:env]) do |stream, chunk|
      sql_dump.write(chunk) if stream == :stdout
      LOGGER.warn("#{name} stderr: #{chunk}") if stream == :stderr
    end
    sql_dump.close
    LOGGER.debug("Backup completed for container #{name}.")
  end

  private

  def backup_command
    if @backup_command.respond_to?(engine.to_sym)
      return @backup_command.send(engine.to_sym, login: login, password: password, database: database)
    elsif engine == 'custom'
      return @backup_command.custom(command: labels['baktainer.command']) || raise('Custom command not defined. Set docker label bt_command.')
    else
      raise "Unsupported engine: #{engine}"
    end
  end
end

# :NODOC:
class Containers
  def self.find_all
    LOGGER.debug('Searching for containers with backup labels.')
    containers = Docker::Container.all.select do |container|
      container.info['Labels']['baktainer.backup'] == 'true'
    end
    LOGGER.debug("Found #{containers.size} containers with backup labels.")
    LOGGER.debug(containers.first.class)
    containers.map do |container|
      Baktainer::Container.new(container)
    end
  end
end
