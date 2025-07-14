# frozen_string_literal: true

# Load coverage if enabled
require_relative 'support/coverage' if ENV['COVERAGE']

require 'rspec'
require 'docker-api'
require 'webmock/rspec'
require 'factory_bot'

# Add lib directory to load path
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

# Require the main application files
require 'baktainer'
require 'baktainer/logger'
require 'baktainer/container'
require 'baktainer/backup_command'

# Configure RSpec
RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = 'spec/examples.txt'
  config.disable_monkey_patching!
  config.warnings = true

  # Configure FactoryBot
  config.include FactoryBot::Syntax::Methods
  config.before(:suite) do
    FactoryBot.definition_file_paths = [File.expand_path('fixtures', __dir__)]
    FactoryBot.find_definitions
  end

  # Configure WebMock based on test type
  config.before(:each) do |example|
    if example.metadata[:integration]
      # Allow localhost connections for integration tests
      WebMock.disable_net_connect!(allow_localhost: true, allow: ['127.0.0.1', 'localhost'])
    else
      # Completely disable network connections for unit tests
      WebMock.disable_net_connect!(allow_localhost: false)
    end
  end

  # Clean up test environment
  config.before(:each) do
    # Reset environment variables
    ENV.delete('BT_DOCKER_URL')
    ENV.delete('BT_SSL')
    ENV.delete('BT_CRON')
    ENV.delete('BT_THREADS')
    ENV.delete('BT_LOG_LEVEL')
    ENV.delete('BT_BACKUP_DIR')
    
    # Clear Docker configuration and set to localhost for tests
    Docker.reset_connection!
    Docker.url = 'unix:///var/run/docker.sock'
  end

  config.after(:each) do
    # Clean up any test files
    FileUtils.rm_rf(Dir.glob('/tmp/baktainer_test_*'))
  end
end

# Test helper methods
module BaktainerTestHelpers
  def mock_docker_container(labels = {})
    container_info = {
      'Id' => '1234567890abcdef',
      'Names' => ['/test-container'],
      'State' => { 'Status' => 'running' },
      'Labels' => {
        'baktainer.backup' => 'true',
        'baktainer.db.engine' => 'postgres',
        'baktainer.db.name' => 'testdb',
        'baktainer.db.user' => 'testuser',
        'baktainer.db.password' => 'testpass'
      }.merge(labels || {})
    }

    container = double('Docker::Container')
    allow(container).to receive(:info).and_return(container_info)
    allow(container).to receive(:id).and_return(container_info['Id'])
    allow(container).to receive(:exec) do |cmd, env: nil, &block|
      block.call(:stdout, 'test backup data') if block
    end
    
    container
  end

  def create_test_backup_dir
    test_dir = "/tmp/baktainer_test_#{Time.now.to_i}"
    FileUtils.mkdir_p(test_dir)
    test_dir
  end

  def with_env(env_vars)
    original_env = {}
    env_vars.each do |key, value|
      original_env[key] = ENV[key]
      ENV[key] = value
    end
    
    yield
  ensure
    original_env.each do |key, value|
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end
  end
end

RSpec.configure do |config|
  config.include BaktainerTestHelpers
end