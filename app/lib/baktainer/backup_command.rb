# frozen_string_literal: true

require 'baktainer/mysql'
require 'baktainer/postgres'
require 'baktainer/mariadb'
require 'baktainer/sqlite'

# This class is responsible for generating the backup command for the database engine
# It uses the environment variables to set the necessary parameters for the backup command
# The class methods return a hash with the environment variables and the command to run
# The class methods are used in the Baktainer::Container class to generate the backup command
class Baktainer::BackupCommand
  # Whitelist of allowed backup commands for security
  ALLOWED_COMMANDS = %w[
    mysqldump
    pg_dump
    pg_dumpall
    sqlite3
    mongodump
  ].freeze

  def custom(command: nil)
    raise ArgumentError, "Command cannot be nil" if command.nil?
    raise ArgumentError, "Command cannot be empty" if command.strip.empty?

    # Split command safely and validate
    cmd_parts = sanitize_command(command)
    validate_command_security(cmd_parts)

    {
      env: [],
      cmd: cmd_parts
    }
  end

  private

  def sanitize_command(command)
    # Remove dangerous characters and split properly
    sanitized = command.gsub(/[;&|`$(){}\[\]<>]/, '')
    parts = sanitized.split(/\s+/).reject(&:empty?)
    
    # Remove any null bytes or control characters
    parts.map { |part| part.tr("\x00-\x1f\x7f", '') }
  end

  def validate_command_security(cmd_parts)
    return if cmd_parts.empty?

    command_name = cmd_parts[0]
    
    # Check if command is in whitelist
    unless ALLOWED_COMMANDS.include?(command_name)
      raise SecurityError, "Command '#{command_name}' is not allowed. Allowed commands: #{ALLOWED_COMMANDS.join(', ')}"
    end

    # Check for suspicious patterns in arguments
    cmd_parts[1..].each do |arg|
      if arg.match?(/[;&|`$()]/) || arg.include?('..') || arg.start_with?('/')
        raise SecurityError, "Potentially dangerous argument detected: #{arg}"
      end
    end
  end
end
