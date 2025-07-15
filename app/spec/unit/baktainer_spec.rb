# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Baktainer::Runner do
  let(:default_options) do
    {
      url: 'unix:///var/run/docker.sock',
      ssl: false,
      ssl_options: {},
      threads: 5
    }
  end
  
  let(:mock_logger) { double('Logger', debug: nil, info: nil, warn: nil, error: nil, level: Logger::INFO, 'level=': nil) }
  let(:mock_config) { double('Configuration', docker_url: 'unix:///var/run/docker.sock', ssl_enabled?: false, threads: 5, log_level: 'info', backup_dir: '/backups', compress?: true, encryption_enabled?: false) }
  let(:mock_thread_pool) { double('ThreadPool', post: nil, shutdown: nil, kill: nil) }
  let(:mock_backup_monitor) { double('BackupMonitor', start_monitoring: nil, stop_monitoring: nil, start_backup: nil, complete_backup: nil, fail_backup: nil, get_metrics_summary: {}) }
  let(:mock_backup_rotation) { double('BackupRotation', cleanup: { deleted_count: 0, freed_space: 0 }) }
  let(:mock_dependency_container) { double('DependencyContainer') }
  
  # Mock Docker API calls at the beginning
  before do
    allow(Docker).to receive(:version).and_return({ 'Version' => '20.10.0' })
    allow(Docker::Container).to receive(:all).and_return([])
    
    # Mock dependency container and its services
    allow(Baktainer::DependencyContainer).to receive(:new).and_return(mock_dependency_container)
    allow(mock_dependency_container).to receive(:configure).and_return(mock_dependency_container)
    allow(mock_dependency_container).to receive(:get).with(:logger).and_return(mock_logger)
    allow(mock_dependency_container).to receive(:get).with(:configuration).and_return(mock_config)
    allow(mock_dependency_container).to receive(:get).with(:thread_pool).and_return(mock_thread_pool)
    allow(mock_dependency_container).to receive(:get).with(:backup_monitor).and_return(mock_backup_monitor)
    allow(mock_dependency_container).to receive(:get).with(:backup_rotation).and_return(mock_backup_rotation)
    
    # Mock Docker URL setting
    allow(Docker).to receive(:url=)
  end
  
  let(:runner) { described_class.new(**default_options) }

  describe '#initialize' do
    it 'sets default values' do
      expect(runner.instance_variable_get(:@url)).to eq('unix:///var/run/docker.sock')
      expect(runner.instance_variable_get(:@ssl)).to be false
      expect(runner.instance_variable_get(:@ssl_options)).to eq({})
    end

    it 'configures Docker URL' do
      expect(Docker).to receive(:url=).with('unix:///var/run/docker.sock')
      described_class.new(**default_options)
    end

    it 'gets thread pool from dependency container' do
      pool = runner.instance_variable_get(:@pool)
      expect(pool).to eq(mock_thread_pool)
    end

    it 'sets up SSL when enabled' do
      ssl_options = {
        url: 'https://docker.example.com:2376',
        ssl: true,
        ssl_options: { ca_file: 'ca.pem', client_cert: 'cert.pem', client_key: 'key.pem' }
      }
      
      # Generate valid test certificates
      require 'openssl'
      key = OpenSSL::PKey::RSA.new(2048)
      cert = OpenSSL::X509::Certificate.new
      cert.version = 2
      cert.serial = 1
      cert.subject = OpenSSL::X509::Name.parse('/CN=test')
      cert.issuer = cert.subject
      cert.public_key = key.public_key
      cert.not_before = Time.now
      cert.not_after = Time.now + 3600
      cert.sign(key, OpenSSL::Digest::SHA256.new)
      
      cert_pem = cert.to_pem
      key_pem = key.to_pem
      
      # Mock SSL-enabled configuration with valid certificates
      ssl_config = double('Configuration', 
        docker_url: 'https://docker.example.com:2376', 
        ssl_enabled?: true, 
        threads: 5, 
        log_level: 'info', 
        backup_dir: '/backups', 
        compress?: true, 
        encryption_enabled?: false,
        ssl_ca: cert_pem,
        ssl_cert: cert_pem, 
        ssl_key: key_pem
      )
      
      mock_docker_client = double('Docker')
      
      ssl_dependency_container = double('DependencyContainer')
      allow(Baktainer::DependencyContainer).to receive(:new).and_return(ssl_dependency_container)
      allow(ssl_dependency_container).to receive(:configure).and_return(ssl_dependency_container)
      allow(ssl_dependency_container).to receive(:get).with(:logger).and_return(mock_logger)
      allow(ssl_dependency_container).to receive(:get).with(:configuration).and_return(ssl_config)
      allow(ssl_dependency_container).to receive(:get).with(:thread_pool).and_return(mock_thread_pool)
      allow(ssl_dependency_container).to receive(:get).with(:backup_monitor).and_return(mock_backup_monitor)
      allow(ssl_dependency_container).to receive(:get).with(:backup_rotation).and_return(mock_backup_rotation)
      allow(ssl_dependency_container).to receive(:get).with(:docker_client).and_return(mock_docker_client)
      
      expect { described_class.new(**ssl_options) }.not_to raise_error
    end

    it 'gets logger from dependency container' do
      logger = runner.instance_variable_get(:@logger)
      expect(logger).to eq(mock_logger)
    end
  end

  describe '#perform_backup' do
    let(:mock_container) { instance_double(Baktainer::Container, name: 'test-container', engine: 'postgres') }
    let(:mock_future) { double('Future', value: nil, reason: nil) }
    
    before do
      allow(Baktainer::Containers).to receive(:find_all).and_return([mock_container])
      allow(mock_container).to receive(:backup)
      allow(mock_thread_pool).to receive(:post).and_yield.and_return(mock_future)
    end

    it 'finds all containers and backs them up' do
      expect(Baktainer::Containers).to receive(:find_all).and_return([mock_container])
      expect(mock_container).to receive(:backup)
      
      runner.perform_backup
    end

    it 'handles backup errors gracefully' do
      allow(mock_container).to receive(:backup).and_raise(StandardError.new('Test error'))
      
      expect { runner.perform_backup }.not_to raise_error
    end

    it 'uses thread pool for concurrent backups' do
      containers = Array.new(3) { |i| 
        instance_double(Baktainer::Container, name: "container-#{i}", engine: 'postgres', backup: nil)
      }
      
      allow(Baktainer::Containers).to receive(:find_all).and_return(containers)
      
      containers.each do |container|
        expect(container).to receive(:backup)
      end
      
      runner.perform_backup
    end
  end

  describe '#run' do
    let(:mock_cron) { double('CronCalc') }
    
    before do
      allow(CronCalc).to receive(:new).and_return(mock_cron)
      allow(mock_cron).to receive(:next).and_return(Time.now + 1)
      allow(runner).to receive(:sleep)
      allow(runner).to receive(:perform_backup)
    end

    it 'uses default cron schedule when BT_CRON not set' do
      expect(CronCalc).to receive(:new).with('0 0 * * *').and_return(mock_cron)
      
      # Stop the infinite loop after first iteration
      allow(runner).to receive(:loop).and_yield
      
      runner.run
    end

    it 'uses BT_CRON environment variable when set' do
      with_env('BT_CRON' => '0 12 * * *') do
        expect(CronCalc).to receive(:new).with('0 12 * * *').and_return(mock_cron)
        
        allow(runner).to receive(:loop).and_yield
        
        runner.run
      end
    end

    it 'handles invalid cron format gracefully' do
      with_env('BT_CRON' => 'invalid-cron') do
        expect(CronCalc).to receive(:new).with('invalid-cron').and_raise(StandardError)
        
        allow(runner).to receive(:loop).and_yield
        
        expect { runner.run }.not_to raise_error
      end
    end

    it 'calculates sleep duration correctly' do
      future_time = Time.now + 3600 # 1 hour from now
      allow(Time).to receive(:now).and_return(Time.now)
      allow(mock_cron).to receive(:next).and_return(future_time)
      
      allow(runner).to receive(:loop).and_yield
      
      expect(runner).to receive(:sleep) do |duration|
        expect(duration).to be_within(1).of(3600)
      end
      
      runner.run
    end
  end

  describe '#setup_ssl (private)' do
    context 'when SSL is disabled' do
      it 'does not use SSL configuration' do
        runner # instantiate with default options (SSL disabled)
        # For non-SSL runner, docker client is not requested from dependency container
        expect(mock_dependency_container).not_to have_received(:get).with(:docker_client)
      end
    end

    context 'when SSL is enabled' do
      let(:ssl_config) do
        double('Configuration', 
          docker_url: 'https://docker.example.com:2376', 
          ssl_enabled?: true, 
          threads: 5, 
          log_level: 'info', 
          backup_dir: '/backups', 
          compress?: true, 
          encryption_enabled?: false,
          ssl_ca: 'test_ca_cert',
          ssl_cert: 'test_client_cert', 
          ssl_key: 'test_client_key'
        )
      end

      it 'creates runner with SSL configuration' do
        # Generate valid test certificates for SSL configuration
        require 'openssl'
        key = OpenSSL::PKey::RSA.new(2048)
        cert = OpenSSL::X509::Certificate.new
        cert.version = 2
        cert.serial = 1
        cert.subject = OpenSSL::X509::Name.parse('/CN=test')
        cert.issuer = cert.subject
        cert.public_key = key.public_key
        cert.not_before = Time.now
        cert.not_after = Time.now + 3600
        cert.sign(key, OpenSSL::Digest::SHA256.new)
        
        cert_pem = cert.to_pem
        key_pem = key.to_pem
        
        ssl_config_with_certs = double('Configuration', 
          docker_url: 'https://docker.example.com:2376', 
          ssl_enabled?: true, 
          threads: 5, 
          log_level: 'info', 
          backup_dir: '/backups', 
          compress?: true, 
          encryption_enabled?: false,
          ssl_ca: cert_pem,
          ssl_cert: cert_pem, 
          ssl_key: key_pem
        )
        
        mock_docker_client = double('Docker')
        
        ssl_dependency_container = double('DependencyContainer')
        allow(Baktainer::DependencyContainer).to receive(:new).and_return(ssl_dependency_container)
        allow(ssl_dependency_container).to receive(:configure).and_return(ssl_dependency_container)
        allow(ssl_dependency_container).to receive(:get).with(:logger).and_return(mock_logger)
        allow(ssl_dependency_container).to receive(:get).with(:configuration).and_return(ssl_config_with_certs)
        allow(ssl_dependency_container).to receive(:get).with(:thread_pool).and_return(mock_thread_pool)
        allow(ssl_dependency_container).to receive(:get).with(:backup_monitor).and_return(mock_backup_monitor)
        allow(ssl_dependency_container).to receive(:get).with(:backup_rotation).and_return(mock_backup_rotation)
        allow(ssl_dependency_container).to receive(:get).with(:docker_client).and_return(mock_docker_client)
        
        ssl_options = { url: 'https://docker.example.com:2376', ssl: true, ssl_options: {} }
        
        expect { described_class.new(**ssl_options) }.not_to raise_error
      end
    end
  end
end