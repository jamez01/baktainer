# frozen_string_literal: true

require 'spec_helper'
require 'baktainer/backup_rotation'

RSpec.describe Baktainer::BackupRotation do
  let(:logger) { double('Logger', info: nil, debug: nil, warn: nil, error: nil) }
  let(:test_backup_dir) { create_test_backup_dir }
  let(:config) { double('Configuration', backup_dir: test_backup_dir) }
  let(:rotation) { described_class.new(logger, config) }
  
  before do
    # Mock environment variables
    stub_const('ENV', ENV.to_hash.merge(
      'BT_RETENTION_DAYS' => '7',
      'BT_RETENTION_COUNT' => '5',
      'BT_MIN_FREE_SPACE_GB' => '1'
    ))
  end
  
  after do
    FileUtils.rm_rf(test_backup_dir) if Dir.exist?(test_backup_dir)
  end
  
  describe '#initialize' do
    it 'sets retention policies from environment' do
      expect(rotation.retention_days).to eq(7)
      expect(rotation.retention_count).to eq(5)
      expect(rotation.min_free_space_gb).to eq(1)
    end
    
    it 'uses defaults when environment not set' do
      stub_const('ENV', {})
      rotation = described_class.new(logger, config)
      
      expect(rotation.retention_days).to eq(30)
      expect(rotation.retention_count).to eq(0)
      expect(rotation.min_free_space_gb).to eq(10)
    end
  end
  
  describe '#cleanup' do
    # Each test creates its own isolated backup files
    
    before do
      # Ensure completely clean state for each test
      FileUtils.rm_rf(test_backup_dir) if Dir.exist?(test_backup_dir)
      FileUtils.mkdir_p(test_backup_dir)
    end
    before do
      # Create test backup files with different ages
      create_test_backups
    end
    
    context 'cleanup by age' do
      let(:rotation) do
        # Override environment to only test age-based cleanup
        stub_const('ENV', ENV.to_hash.merge(
          'BT_RETENTION_DAYS' => '7',
          'BT_RETENTION_COUNT' => '0',  # Disable count-based cleanup
          'BT_MIN_FREE_SPACE_GB' => '0' # Disable space cleanup
        ))
        described_class.new(logger, config)
      end
      it 'deletes backups older than retention days' do
        # Mock get_free_space to ensure space cleanup doesn't run
        allow(rotation).to receive(:get_free_space).and_return(1024 * 1024 * 1024 * 1024) # 1TB
        
        # Count existing old files before we create our test file
        files_before = Dir.glob(File.join(test_backup_dir, '**', '*.sql'))
        old_files_before = files_before.select do |file|
          File.mtime(file) < (Time.now - (7 * 24 * 60 * 60))
        end.count
        
        # Create an old backup (10 days ago)
        old_date = (Date.today - 10).strftime('%Y-%m-%d')
        old_dir = File.join(test_backup_dir, old_date)
        FileUtils.mkdir_p(old_dir)
        old_file = File.join(old_dir, 'test-app-1234567890.sql')
        File.write(old_file, 'old backup data')
        
        # Set file modification time to 10 days ago
        old_time = Time.now - (10 * 24 * 60 * 60)
        File.utime(old_time, old_time, old_file)
        
        result = rotation.cleanup
        
        # Expect to delete our file plus any pre-existing old files
        expect(result[:deleted_count]).to eq(old_files_before + 1)
        expect(File.exist?(old_file)).to be false
      end
      
      it 'keeps backups within retention period' do
        # Clean up any old files from create_test_backups first
        Dir.glob(File.join(test_backup_dir, '**', '*.sql')).each do |file|
          File.delete(file) if File.mtime(file) < (Time.now - (7 * 24 * 60 * 60))
        end
        
        # Mock get_free_space to ensure space cleanup doesn't run
        allow(rotation).to receive(:get_free_space).and_return(1024 * 1024 * 1024 * 1024) # 1TB
        
        # Create a recent backup (2 days ago)
        recent_date = (Date.today - 2).strftime('%Y-%m-%d')
        recent_dir = File.join(test_backup_dir, recent_date)
        FileUtils.mkdir_p(recent_dir)
        recent_file = File.join(recent_dir, 'recent-app-1234567890.sql')
        File.write(recent_file, 'recent backup data')
        
        # Set file modification time to 2 days ago
        recent_time = Time.now - (2 * 24 * 60 * 60)
        File.utime(recent_time, recent_time, recent_file)
        
        result = rotation.cleanup
        
        expect(result[:deleted_count]).to eq(0)
        expect(File.exist?(recent_file)).to be true
      end
    end
    
    context 'cleanup by count' do
      let(:rotation) do
        # Override environment to only test count-based cleanup
        stub_const('ENV', ENV.to_hash.merge(
          'BT_RETENTION_DAYS' => '0',  # Disable age-based cleanup
          'BT_RETENTION_COUNT' => '5',
          'BT_MIN_FREE_SPACE_GB' => '0' # Disable space cleanup
        ))
        described_class.new(logger, config)
      end
      it 'keeps only specified number of recent backups per container' do
        # Create 8 backups for the same container
        date_dir = File.join(test_backup_dir, Date.today.strftime('%Y-%m-%d'))
        FileUtils.mkdir_p(date_dir)
        
        8.times do |i|
          timestamp = Time.now.to_i - (i * 3600) # 1 hour apart
          backup_file = File.join(date_dir, "myapp-#{timestamp}.sql")
          File.write(backup_file, "backup data #{i}")
          
          # Set different modification times
          mtime = Time.now - (i * 3600)
          File.utime(mtime, mtime, backup_file)
        end
        
        result = rotation.cleanup('myapp')
        
        # Should keep only 5 most recent backups
        expect(result[:deleted_count]).to eq(3)
        
        remaining_files = Dir.glob(File.join(date_dir, 'myapp-*.sql'))
        expect(remaining_files.length).to eq(5)
      end
      
      it 'handles multiple containers independently' do
        date_dir = File.join(test_backup_dir, Date.today.strftime('%Y-%m-%d'))
        FileUtils.mkdir_p(date_dir)
        
        # Create backups for two containers
        ['app1', 'app2'].each do |app|
          6.times do |i|
            timestamp = Time.now.to_i - (i * 3600)
            backup_file = File.join(date_dir, "#{app}-#{timestamp}.sql")
            File.write(backup_file, "backup data")
            
            mtime = Time.now - (i * 3600)
            File.utime(mtime, mtime, backup_file)
          end
        end
        
        result = rotation.cleanup
        
        # Should delete 1 backup from each container (6 - 5 = 1)
        expect(result[:deleted_count]).to eq(2)
        
        expect(Dir.glob(File.join(date_dir, 'app1-*.sql')).length).to eq(5)
        expect(Dir.glob(File.join(date_dir, 'app2-*.sql')).length).to eq(5)
      end
    end
    
    context 'cleanup for space' do
      it 'deletes oldest backups when disk space is low' do
        # Mock low disk space
        allow(rotation).to receive(:get_free_space).and_return(500 * 1024 * 1024) # 500MB
        
        date_dir = File.join(test_backup_dir, Date.today.strftime('%Y-%m-%d'))
        FileUtils.mkdir_p(date_dir)
        
        # Create backups with different ages
        3.times do |i|
          timestamp = Time.now.to_i - (i * 86400) # 1 day apart
          backup_file = File.join(date_dir, "app-#{timestamp}.sql")
          File.write(backup_file, "backup data " * 1000) # Make it larger
          
          mtime = Time.now - (i * 86400)
          File.utime(mtime, mtime, backup_file)
        end
        
        result = rotation.cleanup
        
        # Should delete at least one backup to free space
        expect(result[:deleted_count]).to be > 0
      end
    end
    
    context 'empty directory cleanup' do
      it 'removes empty date directories' do
        empty_dir = File.join(test_backup_dir, '2024-01-01')
        FileUtils.mkdir_p(empty_dir)
        
        rotation.cleanup
        
        expect(Dir.exist?(empty_dir)).to be false
      end
      
      it 'keeps directories with backup files' do
        date_dir = File.join(test_backup_dir, '2024-01-01')
        FileUtils.mkdir_p(date_dir)
        File.write(File.join(date_dir, 'app-123.sql'), 'data')
        
        rotation.cleanup
        
        expect(Dir.exist?(date_dir)).to be true
      end
    end
  end
  
  describe '#get_backup_statistics' do
    before do
      # Ensure clean state
      FileUtils.rm_rf(test_backup_dir) if Dir.exist?(test_backup_dir)
      FileUtils.mkdir_p(test_backup_dir)
      # Create test backups
      create_test_backup_structure
    end
    
    it 'returns comprehensive backup statistics' do
      stats = rotation.get_backup_statistics
      
      expect(stats[:total_backups]).to eq(4)
      expect(stats[:total_size]).to be > 0
      expect(stats[:containers].keys).to contain_exactly('app1', 'app2')
      expect(stats[:containers]['app1'][:count]).to eq(2)
      expect(stats[:containers]['app2'][:count]).to eq(2)
      expect(stats[:oldest_backup]).to be_a(Time)
      expect(stats[:newest_backup]).to be_a(Time)
    end
    
    it 'groups statistics by date' do
      stats = rotation.get_backup_statistics
      
      expect(stats[:by_date].keys.length).to eq(2)
      stats[:by_date].each do |date, info|
        expect(info[:count]).to be > 0
        expect(info[:size]).to be > 0
      end
    end
  end
  
  private
  
  def create_test_backups
    # Helper to create test backup structure
    dates = [Date.today, Date.today - 1, Date.today - 10]
    
    dates.each do |date|
      date_dir = File.join(test_backup_dir, date.strftime('%Y-%m-%d'))
      FileUtils.mkdir_p(date_dir)
      
      # Create backup file
      timestamp = date.to_time.to_i
      backup_file = File.join(date_dir, "test-app-#{timestamp}.sql")
      File.write(backup_file, "backup data for #{date}")
      
      # Set file modification time
      File.utime(date.to_time, date.to_time, backup_file)
    end
  end
  
  def create_test_backup_structure
    # Create backups for multiple containers across multiple dates
    dates = [Date.today, Date.today - 1]
    containers = ['app1', 'app2']
    
    dates.each do |date|
      date_dir = File.join(test_backup_dir, date.strftime('%Y-%m-%d'))
      FileUtils.mkdir_p(date_dir)
      
      containers.each do |container|
        timestamp = date.to_time.to_i
        backup_file = File.join(date_dir, "#{container}-#{timestamp}.sql.gz")
        File.write(backup_file, "compressed backup data")
        
        # Create metadata file
        metadata = {
          container_name: container,
          timestamp: date.to_time.iso8601,
          compressed: true
        }
        File.write("#{backup_file}.meta", metadata.to_json)
      end
    end
  end
end