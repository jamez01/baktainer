# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Backup Workflow Integration', :integration do

  let(:test_backup_dir) { create_test_backup_dir }
  
  # Mock containers for integration testing
  let(:postgres_container_info) do
    {
      'Id' => 'postgres123',
      'Names' => ['/baktainer-test-postgres'],
      'State' => { 'Status' => 'running' },
      'Labels' => {
        'baktainer.backup' => 'true',
        'baktainer.db.engine' => 'postgres',
        'baktainer.db.name' => 'testdb',
        'baktainer.db.user' => 'testuser',
        'baktainer.db.password' => 'testpass',
        'baktainer.name' => 'TestPostgres'
      }
    }
  end
  
  let(:mysql_container_info) do
    {
      'Id' => 'mysql123',
      'Names' => ['/baktainer-test-mysql'],
      'State' => { 'Status' => 'running' },
      'Labels' => {
        'baktainer.backup' => 'true',
        'baktainer.db.engine' => 'mysql',
        'baktainer.db.name' => 'testdb',
        'baktainer.db.user' => 'testuser',
        'baktainer.db.password' => 'testpass',
        'baktainer.name' => 'TestMySQL'
      }
    }
  end
  
  let(:sqlite_container_info) do
    {
      'Id' => 'sqlite123',
      'Names' => ['/baktainer-test-sqlite'],
      'State' => { 'Status' => 'running' },
      'Labels' => {
        'baktainer.backup' => 'true',
        'baktainer.db.engine' => 'sqlite',
        'baktainer.db.name' => '/data/test.db',
        'baktainer.name' => 'TestSQLite'
      }
    }
  end
  
  let(:no_backup_container_info) do
    {
      'Id' => 'nobackup123',
      'Names' => ['/baktainer-test-no-backup'],
      'State' => { 'Status' => 'running' },
      'Labels' => {
        'some.other.label' => 'value'
      }
    }
  end
  
  let(:mock_containers) do
    [
      mock_docker_container(postgres_container_info['Labels']),
      mock_docker_container(mysql_container_info['Labels']),
      mock_docker_container(sqlite_container_info['Labels']),
      mock_docker_container(no_backup_container_info['Labels'])
    ]
  end
  
  before(:each) do
    stub_const('ENV', ENV.to_hash.merge('BT_BACKUP_DIR' => test_backup_dir))
    
    # Disable all network connections for integration tests
    WebMock.disable_net_connect!
    
    # Mock the Docker API calls to avoid HTTP connections
    allow(Docker).to receive(:version).and_return({ 'Version' => '20.10.0' })
    allow(Docker::Container).to receive(:all).and_return(mock_containers)
    
    # Set up individual container mocks with correct info
    allow(mock_containers[0]).to receive(:info).and_return(postgres_container_info)
    allow(mock_containers[1]).to receive(:info).and_return(mysql_container_info)
    allow(mock_containers[2]).to receive(:info).and_return(sqlite_container_info)
    allow(mock_containers[3]).to receive(:info).and_return(no_backup_container_info)
  end
  
  after(:each) do
    FileUtils.rm_rf(test_backup_dir) if Dir.exist?(test_backup_dir)
  end

  describe 'Container Discovery' do
    it 'finds containers with backup labels' do
      containers = Baktainer::Containers.find_all
      
      expect(containers).not_to be_empty
      expect(containers.length).to eq(3) # Only containers with backup labels
      
      # Should find the test containers with backup labels
      container_names = containers.map(&:name)
      expect(container_names).to include('baktainer-test-postgres')
      expect(container_names).to include('baktainer-test-mysql')
      expect(container_names).to include('baktainer-test-sqlite')
      
      # Should not include containers without backup labels
      expect(container_names).not_to include('baktainer-test-no-backup')
    end

    it 'correctly parses container labels' do
      containers = Baktainer::Containers.find_all
      postgres_container = containers.find { |c| c.name == 'baktainer-test-postgres' }
      
      expect(postgres_container).not_to be_nil
      expect(postgres_container.engine).to eq('postgres')
      expect(postgres_container.database).to eq('testdb')
      expect(postgres_container.user).to eq('testuser')
      expect(postgres_container.password).to eq('testpass')
    end
  end

  describe 'PostgreSQL Backup' do
    let(:postgres_container) do
      containers = Baktainer::Containers.find_all
      containers.find { |c| c.engine == 'postgres' }
    end
    
    before do
      # Add fixed time for consistent test results
      allow(Date).to receive(:today).and_return(Date.new(2024, 1, 15))
      allow(Time).to receive(:now).and_return(Time.new(2024, 1, 15, 12, 0, 0))
    end

    it 'creates a valid PostgreSQL backup' do
      expect(postgres_container).not_to be_nil
      
      postgres_container.backup
      
      backup_files = Dir.glob(File.join(test_backup_dir, '**', '*TestPostgres*.sql.gz'))
      expect(backup_files).not_to be_empty
      
      # Read compressed content
      require 'zlib'
      backup_content = Zlib::GzipReader.open(backup_files.first) { |gz| gz.read }
      expect(backup_content).to eq('test backup data') # From mocked exec
    end

    it 'generates correct backup command' do
      expect(postgres_container).not_to be_nil
      
      command = postgres_container.send(:backup_command)
      
      expect(command[:env]).to include('PGPASSWORD=testpass')
      expect(command[:cmd]).to eq(['pg_dump', '-U', 'testuser', '-d', 'testdb'])
    end
  end

  describe 'MySQL Backup' do
    let(:mysql_container) do
      containers = Baktainer::Containers.find_all
      containers.find { |c| c.engine == 'mysql' }
    end
    
    before do
      # Add fixed time for consistent test results
      allow(Date).to receive(:today).and_return(Date.new(2024, 1, 15))
      allow(Time).to receive(:now).and_return(Time.new(2024, 1, 15, 12, 0, 0))
    end

    it 'creates a valid MySQL backup' do
      expect(mysql_container).not_to be_nil
      
      mysql_container.backup
      
      backup_files = Dir.glob(File.join(test_backup_dir, '**', '*TestMySQL*.sql.gz'))
      expect(backup_files).not_to be_empty
      
      # Read compressed content
      require 'zlib'
      backup_content = Zlib::GzipReader.open(backup_files.first) { |gz| gz.read }
      expect(backup_content).to eq('test backup data') # From mocked exec
    end

    it 'generates correct backup command' do
      expect(mysql_container).not_to be_nil
      
      command = mysql_container.send(:backup_command)
      
      expect(command[:env]).to eq([])
      expect(command[:cmd]).to eq(['mysqldump', '-u', 'testuser', '-ptestpass', 'testdb'])
    end
  end

  describe 'SQLite Backup' do
    let(:sqlite_container) do
      containers = Baktainer::Containers.find_all
      containers.find { |c| c.engine == 'sqlite' }
    end
    
    before do
      # Add fixed time for consistent test results
      allow(Date).to receive(:today).and_return(Date.new(2024, 1, 15))
      allow(Time).to receive(:now).and_return(Time.new(2024, 1, 15, 12, 0, 0))
    end

    it 'creates a valid SQLite backup' do
      expect(sqlite_container).not_to be_nil
      
      sqlite_container.backup
      
      backup_files = Dir.glob(File.join(test_backup_dir, '**', '*TestSQLite*.sql.gz'))
      expect(backup_files).not_to be_empty
      
      # Read compressed content
      require 'zlib'
      backup_content = Zlib::GzipReader.open(backup_files.first) { |gz| gz.read }
      expect(backup_content).to eq('test backup data') # From mocked exec
    end

    it 'generates correct backup command' do
      expect(sqlite_container).not_to be_nil
      
      command = sqlite_container.send(:backup_command)
      
      expect(command[:env]).to eq([])
      expect(command[:cmd]).to eq(['sqlite3', '/data/test.db', '.dump'])
    end
  end

  describe 'Full Backup Process' do
    let(:runner) do
      Baktainer::Runner.new(
        url: 'unix:///var/run/docker.sock',
        ssl: false,
        ssl_options: {},
        threads: 3
      )
    end
    
    before do
      # Add fixed time for consistent test results
      allow(Date).to receive(:today).and_return(Date.new(2024, 1, 15))
      allow(Time).to receive(:now).and_return(Time.new(2024, 1, 15, 12, 0, 0))
    end

    it 'performs backup for all configured containers' do
      runner.perform_backup
      
      # Allow time for threaded backups to complete
      sleep(0.5)
      
      # Check that backup files were created
      backup_files = Dir.glob(File.join(test_backup_dir, '**', '*.sql.gz'))
      expect(backup_files.length).to eq(3) # One for each test database
      
      # Verify file names include timestamp (10-digit unix timestamp)
      backup_files.each do |file|
        expect(File.basename(file)).to match(/\w+-\d{10}\.sql\.gz/)
      end
    end

    it 'creates backup directory structure' do
      runner.perform_backup
      
      # Allow time for threaded backups to complete
      sleep(0.5)
      
      date_dir = File.join(test_backup_dir, '2024-01-15')
      expect(Dir.exist?(date_dir)).to be true
    end

    it 'handles backup errors gracefully' do
      # Create a container that will fail backup
      failing_container = instance_double(Baktainer::Container)
      allow(failing_container).to receive(:name).and_return('failing-container')
      allow(failing_container).to receive(:engine).and_return('postgres')
      allow(failing_container).to receive(:backup).and_raise(StandardError.new('Backup failed'))
      
      allow(Baktainer::Containers).to receive(:find_all).and_return([failing_container])
      
      expect { runner.perform_backup }.not_to raise_error
      
      # Allow time for threaded execution
      sleep(0.1)
    end
  end

  describe 'Error Handling' do
    it 'handles containers that are not running' do
      # Create a stopped container mock
      stopped_container_info = postgres_container_info.dup
      stopped_container_info['State'] = { 'Status' => 'exited' }
      
      stopped_container = mock_docker_container(stopped_container_info['Labels'])
      allow(stopped_container).to receive(:info).and_return(stopped_container_info)
      
      # Override the Docker::Container.all to return the stopped container
      allow(Docker::Container).to receive(:all).and_return([stopped_container])
      
      containers = Baktainer::Containers.find_all
      expect(containers.length).to eq(1) # Should find the container with backup label
      
      stopped_container_wrapper = containers.first
      expect { stopped_container_wrapper.validate }.to raise_error(/not running/)
    end

    it 'handles missing backup directory gracefully' do
      non_existent_dir = '/tmp/non_existent_backup_dir'
      
      # Add fixed time for consistent test results
      allow(Date).to receive(:today).and_return(Date.new(2024, 1, 15))
      allow(Time).to receive(:now).and_return(Time.new(2024, 1, 15, 12, 0, 0))
      
      with_env('BT_BACKUP_DIR' => non_existent_dir) do
        containers = Baktainer::Containers.find_all
        container = containers.first
        
        expect(container).not_to be_nil
        expect { container.backup }.not_to raise_error
        expect(Dir.exist?(File.join(non_existent_dir, '2024-01-15'))).to be true
      end
      
      FileUtils.rm_rf(non_existent_dir) if Dir.exist?(non_existent_dir)
    end
  end

  describe 'Concurrent Backup Execution' do
    before do
      # Add fixed time for consistent test results
      allow(Date).to receive(:today).and_return(Date.new(2024, 1, 15))
      allow(Time).to receive(:now).and_return(Time.new(2024, 1, 15, 12, 0, 0))
    end
    
    it 'executes multiple backups concurrently' do
      runner = Baktainer::Runner.new(threads: 3)
      
      start_time = Time.now
      runner.perform_backup
      
      # Allow time for concurrent execution
      sleep(0.5)
      
      end_time = Time.now
      execution_time = end_time - start_time
      
      # Concurrent execution should complete quickly with mocked containers
      expect(execution_time).to be < 5 # Should complete within 5 seconds
      
      # Verify all backups completed
      backup_files = Dir.glob(File.join(test_backup_dir, '**', '*.sql.gz'))
      expect(backup_files.length).to eq(3)
    end
  end
end