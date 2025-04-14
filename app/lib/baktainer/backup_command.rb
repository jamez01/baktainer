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
  def custom(command: nil)
    {
      env: [],
      cmd: command.split(/\s+/)
    }
  end
end
