# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Baktainer::Container do
  let(:container_info) { build(:docker_container_info) }
  let(:docker_container) { mock_docker_container(container_info['Labels']) }
  let(:container) { described_class.new(docker_container) }

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
        expect { container.validate }.not_to raise_error
      end
    end

    context 'with nil container' do
      let(:container) { described_class.new(nil) }
      
      it 'raises an error' do
        expect { container.validate }.to raise_error('Unable to parse container')
      end
    end

    context 'with stopped container' do
      let(:stopped_container_info) { build(:docker_container_info, :stopped) }
      let(:stopped_docker_container) { mock_docker_container(stopped_container_info['Labels']) }
      
      before do
        allow(stopped_docker_container).to receive(:info).and_return(stopped_container_info)
      end
      
      let(:container) { described_class.new(stopped_docker_container) }
      
      it 'raises an error' do
        expect { container.validate }.to raise_error('Container not running')
      end
    end

    context 'with missing backup label' do
      let(:no_backup_info) { build(:docker_container_info, :no_backup_label) }
      let(:no_backup_container) { mock_docker_container(no_backup_info['Labels']) }
      
      before do
        allow(no_backup_container).to receive(:info).and_return(no_backup_info)
      end
      
      let(:container) { described_class.new(no_backup_container) }
      
      it 'raises an error' do
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
      
      it 'raises an error' do
        expect { container.validate }.to raise_error('DB Engine not defined. Set docker label baktainer.engine.')
      end
    end
  end


  describe '#backup' do
    let(:test_backup_dir) { create_test_backup_dir }
    
    before do
      stub_const('ENV', ENV.to_hash.merge('BT_BACKUP_DIR' => test_backup_dir))
      allow(Date).to receive(:today).and_return(Date.new(2024, 1, 15))
      allow(Time).to receive(:now).and_return(Time.new(2024, 1, 15, 12, 0, 0))
    end
    
    after do
      FileUtils.rm_rf(test_backup_dir) if Dir.exist?(test_backup_dir)
    end

    it 'creates backup directory and file' do
      container.backup
      
      expected_dir = File.join(test_backup_dir, '2024-01-15')
      expected_file = File.join(expected_dir, 'TestApp-1705338000.sql')
      
      expect(Dir.exist?(expected_dir)).to be true
      expect(File.exist?(expected_file)).to be true
    end

    it 'writes backup data to file' do
      container.backup
      
      expected_file = File.join(test_backup_dir, '2024-01-15', 'TestApp-1705338000.sql')
      content = File.read(expected_file)
      
      expect(content).to eq('test backup data')
    end

    it 'uses container name when baktainer.name label is missing' do
      labels_without_name = container_info['Labels'].dup
      labels_without_name.delete('baktainer.name')
      
      allow(docker_container).to receive(:info).and_return(
        container_info.merge('Labels' => labels_without_name)
      )
      
      container.backup
      
      expected_file = File.join(test_backup_dir, '2024-01-15', 'test-container-1705338000.sql')
      expect(File.exist?(expected_file)).to be true
    end
  end

  describe 'Baktainer::Containers.find_all' do
    let(:containers) { [docker_container] }
    
    before do
      allow(Docker::Container).to receive(:all).and_return(containers)
    end

    it 'returns containers with backup label' do
      result = Baktainer::Containers.find_all
      
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
      
      result = Baktainer::Containers.find_all
      
      expect(result.length).to eq(1)
    end

    it 'handles containers with nil labels' do
      nil_labels_container = double('Docker::Container')
      allow(nil_labels_container).to receive(:info).and_return({ 'Labels' => nil })
      
      containers = [docker_container, nil_labels_container]
      allow(Docker::Container).to receive(:all).and_return(containers)
      
      result = Baktainer::Containers.find_all
      
      expect(result.length).to eq(1)
    end
  end
end