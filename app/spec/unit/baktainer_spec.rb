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

    it 'creates fixed thread pool with specified size' do
      pool = runner.instance_variable_get(:@pool)
      expect(pool).to be_a(Concurrent::FixedThreadPool)
    end

    it 'sets up SSL when enabled' do
      ssl_options = {
        url: 'https://docker.example.com:2376',
        ssl: true,
        ssl_options: { ca_file: 'ca.pem', client_cert: 'cert.pem', client_key: 'key.pem' }
      }
      
      # Generate a valid test certificate
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
      
      with_env('BT_CA' => cert_pem, 'BT_CERT' => cert_pem, 'BT_KEY' => key_pem) do
        expect { described_class.new(**ssl_options) }.not_to raise_error
      end
    end

    it 'sets log level from environment' do
      with_env('LOG_LEVEL' => 'debug') do
        described_class.new(**default_options)
        expect(LOGGER.level).to eq(Logger::DEBUG)
      end
    end
  end

  describe '#perform_backup' do
    let(:mock_container) { instance_double(Baktainer::Container, name: 'test-container', engine: 'postgres') }
    
    before do
      allow(Baktainer::Containers).to receive(:find_all).and_return([mock_container])
      allow(mock_container).to receive(:backup)
    end

    it 'finds all containers and backs them up' do
      expect(Baktainer::Containers).to receive(:find_all).and_return([mock_container])
      expect(mock_container).to receive(:backup)
      
      runner.perform_backup
      
      # Allow time for thread execution
      sleep(0.1)
    end

    it 'handles backup errors gracefully' do
      allow(mock_container).to receive(:backup).and_raise(StandardError.new('Test error'))
      
      expect { runner.perform_backup }.not_to raise_error
      
      # Allow time for thread execution
      sleep(0.1)
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
      
      # Allow time for thread execution
      sleep(0.1)
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
      it 'does not configure SSL options' do
        expect(Docker).not_to receive(:options=)
        described_class.new(**default_options)
      end
    end

    context 'when SSL is enabled' do
      let(:ssl_options) do
        {
          url: 'https://docker.example.com:2376',
          ssl: true,
          ssl_options: {}
        }
      end

      it 'configures Docker SSL options' do
        # Generate a valid test certificate
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
        
        with_env('BT_CA' => cert_pem, 'BT_CERT' => cert_pem, 'BT_KEY' => key_pem) do
          expect(Docker).to receive(:options=).with(hash_including(
            client_cert_data: cert_pem,
            client_key_data: key_pem,
            scheme: 'https',
            ssl_verify_peer: true
          ))
          
          described_class.new(**ssl_options)
        end
      end

      it 'handles missing SSL environment variables' do
        # Test with missing environment variables
        expect { described_class.new(**ssl_options) }.to raise_error
      end
    end
  end
end