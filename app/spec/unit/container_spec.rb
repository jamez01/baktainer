# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Baktainer::Container do
  let(:container_info) { build(:docker_container_info) }
  let(:docker_container) { mock_docker_container(container_info['Labels']) }
  let(:mock_logger) { double('Logger', debug: nil, info: nil, warn: nil, error: nil) }
  let(:mock_file_ops) { double('FileSystemOperations') }
  let(:mock_orchestrator) { double('BackupOrchestrator') }
  let(:mock_validator) { double('ContainerValidator') }
  let(:mock_dependency_container) do
    double('DependencyContainer').tap do |container|
      allow(container).to receive(:get).with(:logger).and_return(mock_logger)
      allow(container).to receive(:get).with(:file_system_operations).and_return(mock_file_ops)
      allow(container).to receive(:get).with(:backup_orchestrator).and_return(mock_orchestrator)
    end
  end
  let(:container) { described_class.new(docker_container, mock_dependency_container) }

  before do
    allow(Baktainer::ContainerValidator).to receive(:new).and_return(mock_validator)
    allow(mock_validator).to receive(:validate!).and_return(true)
  end

  describe '#initialize' do
    it 'sets the container instance variable' do
      expect(container.instance_variable_get(:@container)).to eq(docker_container)
    end
  end

  describe '#name' do
    it 'returns the container name without leading slash' do
      expect(container.name).to eq('test-container')
    end

    it 'handles container names without leading slash' do
      allow(docker_container).to receive(:info).and_return(
        container_info.merge('Names' => ['test-container'])
      )
      expect(container.name).to eq('test-container')
    end
  end

  describe '#state' do
    it 'returns the container state' do
      expect(container.state).to eq('running')
    end

    it 'handles missing state information' do
      allow(docker_container).to receive(:info).and_return(
        container_info.merge('State' => nil)
      )
      expect(container.state).to be_nil
    end
  end

  describe '#labels' do
    it 'returns the container labels' do
      expect(container.labels).to be_a(Hash)
      expect(container.labels['baktainer.backup']).to eq('true')
    end
  end

  describe '#engine' do
    it 'returns the database engine from labels' do
      expect(container.engine).to eq('postgres')
    end

    it 'returns nil when engine label is missing' do
      labels_without_engine = container_info['Labels'].dup
      labels_without_engine.delete('baktainer.db.engine')
      
      allow(docker_container).to receive(:info).and_return(
        container_info.merge('Labels' => labels_without_engine)
      )
      
      expect(container.engine).to be_nil
    end
  end

  describe '#database' do
    it 'returns the database name from labels' do
      expect(container.database).to eq('testdb')
    end
  end

  describe '#user' do
    it 'returns the database user from labels' do
      expect(container.user).to eq('testuser')
    end
  end

  describe '#password' do
    it 'returns the database password from labels' do
      expect(container.password).to eq('testpass')
    end
  end

  describe '#validate' do
    context 'with valid container' do
      it 'does not raise an error' do
        allow(mock_validator).to receive(:validate!).and_return(true)
        expect { container.validate }.not_to raise_error
      end
    end

    context 'with validation error' do
      it 'raises an error' do
        allow(mock_validator).to receive(:validate!).and_raise(Baktainer::ValidationError.new('Test error'))
        expect { container.validate }.to raise_error('Test error')
      end
    end

    context 'with nil container' do
      let(:container) { described_class.new(nil, mock_dependency_container) }
      
      it 'raises an error' do
        allow(mock_validator).to receive(:validate!).and_raise(Baktainer::ValidationError.new('Unable to parse container'))
        expect { container.validate }.to raise_error('Unable to parse container')
      end
    end

    context 'with stopped container' do
      let(:stopped_container_info) { build(:docker_container_info, :stopped) }
      let(:stopped_docker_container) { mock_docker_container(stopped_container_info['Labels']) }
      
      before do
        allow(stopped_docker_container).to receive(:info).and_return(stopped_container_info)
      end
      
      let(:container) { described_class.new(stopped_docker_container, mock_dependency_container) }
      
      it 'raises an error' do
        allow(mock_validator).to receive(:validate!).and_raise(Baktainer::ValidationError.new('Container not running'))
        expect { container.validate }.to raise_error('Container not running')
      end
    end

    context 'with missing backup label' do
      let(:no_backup_info) { build(:docker_container_info, :no_backup_label) }
      let(:no_backup_container) { mock_docker_container(no_backup_info['Labels']) }
      
      before do
        allow(no_backup_container).to receive(:info).and_return(no_backup_info)
      end
      
      let(:container) { described_class.new(no_backup_container, mock_dependency_container) }
      
      it 'raises an error' do
        allow(mock_validator).to receive(:validate!).and_raise(Baktainer::ValidationError.new('Backup not enabled for this container. Set docker label baktainer.backup=true'))
        expect { container.validate }.to raise_error('Backup not enabled for this container. Set docker label baktainer.backup=true')
      end
    end

    context 'with missing engine label' do
      let(:labels_without_engine) do
        labels = container_info['Labels'].dup
        labels.delete('baktainer.db.engine')
        labels
      end
      
      before do
        allow(docker_container).to receive(:info).and_return(
          container_info.merge('Labels' => labels_without_engine)
        )
      end
      
      let(:container) { described_class.new(docker_container, mock_dependency_container) }
      
      it 'raises an error' do
        allow(mock_validator).to receive(:validate!).and_raise(Baktainer::ValidationError.new('DB Engine not defined. Set docker label baktainer.engine.'))
        expect { container.validate }.to raise_error('DB Engine not defined. Set docker label baktainer.engine.')
      end
    end
  end


  describe '#backup' do
    before do
      allow(mock_validator).to receive(:validate!).and_return(true)
      allow(mock_orchestrator).to receive(:perform_backup).and_return('/backups/test.sql.gz')
    end

    it 'validates the container before backup' do
      expect(mock_validator).to receive(:validate!)
      container.backup
    end

    it 'delegates backup to orchestrator' do
      expected_metadata = {
        name: 'TestApp',
        engine: 'postgres',
        database: 'testdb',
        user: 'testuser',
        password: 'testpass',
        all: false
      }
      expect(mock_orchestrator).to receive(:perform_backup).with(docker_container, expected_metadata)
      container.backup
    end

    it 'returns the result from orchestrator' do
      expect(mock_orchestrator).to receive(:perform_backup).and_return('/backups/test.sql.gz')
      result = container.backup
      expect(result).to eq('/backups/test.sql.gz')
    end

  end

  describe 'Baktainer::Containers.find_all' do
    let(:containers) { [docker_container] }
    
    before do
      allow(Docker::Container).to receive(:all).and_return(containers)
    end

    it 'returns containers with backup label' do
      result = Baktainer::Containers.find_all(mock_dependency_container)
      
      expect(result).to be_an(Array)
      expect(result.length).to eq(1)
      expect(result.first).to be_a(described_class)
    end

    it 'filters out containers without backup label' do
      no_backup_info = build(:docker_container_info, :no_backup_label)
      no_backup_container = mock_docker_container(no_backup_info['Labels'])
      allow(no_backup_container).to receive(:info).and_return(no_backup_info)
      
      containers = [docker_container, no_backup_container]
      allow(Docker::Container).to receive(:all).and_return(containers)
      
      result = Baktainer::Containers.find_all(mock_dependency_container)
      
      expect(result.length).to eq(1)
    end

    it 'handles containers with nil labels' do
      nil_labels_container = double('Docker::Container')
      allow(nil_labels_container).to receive(:info).and_return({ 'Labels' => nil })
      
      containers = [docker_container, nil_labels_container]
      allow(Docker::Container).to receive(:all).and_return(containers)
      
      result = Baktainer::Containers.find_all(mock_dependency_container)
      
      expect(result.length).to eq(1)
    end
  end
end