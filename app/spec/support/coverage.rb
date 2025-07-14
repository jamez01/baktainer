# frozen_string_literal: true

# Coverage configuration that can be required independently
require 'simplecov'

SimpleCov.start do
  # Coverage configuration
  add_filter '/spec/'
  add_filter '/vendor/'
  add_filter '/coverage/'
  
  # Group files for better reporting
  add_group 'Core Application', 'lib/baktainer.rb'
  add_group 'Container Management', 'lib/baktainer/container.rb'
  add_group 'Backup Commands', %w[
    lib/baktainer/backup_command.rb
    lib/baktainer/mysql.rb
    lib/baktainer/mariadb.rb
    lib/baktainer/postgres.rb
    lib/baktainer/sqlite.rb
  ]
  add_group 'Utilities', 'lib/baktainer/logger.rb'
  
  # Coverage thresholds
  minimum_coverage 80
  minimum_coverage_by_file 70
  
  # Refuse to decrease coverage
  refuse_coverage_drop
  
  # Track branches (Ruby 2.5+)
  enable_coverage :branch if RUBY_VERSION >= '2.5'
  
  # Coverage output formats
  formatter SimpleCov::Formatter::MultiFormatter.new([
    SimpleCov::Formatter::HTMLFormatter,
    SimpleCov::Formatter::SimpleFormatter
  ])
  
  # Track coverage over time
  track_files '{app,lib}/**/*.rb'
  
  # Set command name for tracking
  command_name ENV['COVERAGE_COMMAND'] || 'RSpec'
end

# Only start SimpleCov if COVERAGE environment variable is set
SimpleCov.start if ENV['COVERAGE'] || ENV['CI']