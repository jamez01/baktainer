# frozen_string_literal: true

require 'spec_helper'
require 'baktainer/backup_encryption'

RSpec.describe Baktainer::BackupEncryption do
  let(:logger) { double('Logger', info: nil, debug: nil, warn: nil, error: nil) }
  let(:test_dir) { create_test_backup_dir }
  let(:config) { double('Configuration', encryption_enabled?: encryption_enabled) }
  let(:encryption_enabled) { true }
  
  before do
    allow(config).to receive(:encryption_key).and_return('0123456789abcdef0123456789abcdef') # 32 char hex
    allow(config).to receive(:encryption_key_file).and_return(nil)
    allow(config).to receive(:encryption_passphrase).and_return(nil)
    allow(config).to receive(:key_rotation_enabled?).and_return(false)
  end
  
  after do
    FileUtils.rm_rf(test_dir) if Dir.exist?(test_dir)
  end
  
  describe '#initialize' do
    it 'initializes with encryption enabled' do
      encryption = described_class.new(logger, config)
      info = encryption.encryption_info
      
      expect(info[:enabled]).to be true
      expect(info[:algorithm]).to eq('aes-256-gcm')
      expect(info[:has_key]).to be true
    end
    
    context 'when encryption is disabled' do
      let(:encryption_enabled) { false }
      
      it 'initializes with encryption disabled' do
        encryption = described_class.new(logger, config)
        info = encryption.encryption_info
        
        expect(info[:enabled]).to be false
        expect(info[:has_key]).to be false
      end
    end
  end
  
  describe '#encrypt_file' do
    let(:encryption) { described_class.new(logger, config) }
    let(:test_file) { File.join(test_dir, 'test_backup.sql') }
    let(:test_data) { 'SELECT * FROM users; -- Test backup data' }
    
    before do
      FileUtils.mkdir_p(test_dir)
      File.write(test_file, test_data)
    end
    
    context 'when encryption is enabled' do
      it 'encrypts a backup file' do
        encrypted_file = encryption.encrypt_file(test_file)
        
        expect(encrypted_file).to end_with('.encrypted')
        expect(File.exist?(encrypted_file)).to be true
        expect(File.exist?(test_file)).to be false # Original should be deleted
        expect(File.exist?("#{encrypted_file}.meta")).to be true # Metadata should exist
      end
      
      it 'creates metadata file' do
        encrypted_file = encryption.encrypt_file(test_file)
        metadata_file = "#{encrypted_file}.meta"
        
        expect(File.exist?(metadata_file)).to be true
        metadata = JSON.parse(File.read(metadata_file))
        
        expect(metadata['algorithm']).to eq('aes-256-gcm')
        expect(metadata['original_file']).to eq('test_backup.sql')
        expect(metadata['original_size']).to eq(test_data.bytesize)
        expect(metadata['encrypted_size']).to be > 0
        expect(metadata['key_fingerprint']).to be_a(String)
      end
      
      it 'accepts custom output path' do
        output_path = File.join(test_dir, 'custom_encrypted.dat')
        encrypted_file = encryption.encrypt_file(test_file, output_path)
        
        expect(encrypted_file).to eq(output_path)
        expect(File.exist?(output_path)).to be true
      end
    end
    
    context 'when encryption is disabled' do
      let(:encryption_enabled) { false }
      
      it 'returns original file path without encryption' do
        result = encryption.encrypt_file(test_file)
        
        expect(result).to eq(test_file)
        expect(File.exist?(test_file)).to be true
        expect(File.read(test_file)).to eq(test_data)
      end
    end
  end
  
  describe '#decrypt_file' do
    let(:encryption) { described_class.new(logger, config) }
    let(:test_file) { File.join(test_dir, 'test_backup.sql') }
    let(:test_data) { 'SELECT * FROM users; -- Test backup data for decryption' }
    
    before do
      FileUtils.mkdir_p(test_dir)
      File.write(test_file, test_data)
    end
    
    context 'when encryption is enabled' do
      it 'decrypts an encrypted backup file' do
        # First encrypt the file
        encrypted_file = encryption.encrypt_file(test_file)
        
        # Then decrypt it
        decrypted_file = encryption.decrypt_file(encrypted_file)
        
        expect(File.exist?(decrypted_file)).to be true
        expect(File.read(decrypted_file)).to eq(test_data)
      end
      
      it 'accepts custom output path for decryption' do
        encrypted_file = encryption.encrypt_file(test_file)
        output_path = File.join(test_dir, 'custom_decrypted.sql')
        
        decrypted_file = encryption.decrypt_file(encrypted_file, output_path)
        
        expect(decrypted_file).to eq(output_path)
        expect(File.exist?(output_path)).to be true
        expect(File.read(output_path)).to eq(test_data)
      end
      
      it 'fails with corrupted encrypted file' do
        encrypted_file = encryption.encrypt_file(test_file)
        
        # Corrupt the encrypted file
        File.open(encrypted_file, 'ab') { |f| f.write('corrupted_data') }
        
        expect {
          encryption.decrypt_file(encrypted_file)
        }.to raise_error(Baktainer::EncryptionError, /authentication failed/)
      end
    end
    
    context 'when encryption is disabled' do
      let(:encryption_enabled) { false }
      
      it 'raises error when trying to decrypt' do
        expect {
          encryption.decrypt_file('some_file.encrypted')
        }.to raise_error(Baktainer::EncryptionError, /Encryption is disabled/)
      end
    end
  end
  
  describe '#verify_key' do
    let(:encryption) { described_class.new(logger, config) }
    
    context 'when encryption is enabled' do
      it 'verifies a valid key' do
        result = encryption.verify_key
        
        expect(result[:valid]).to be true
        expect(result[:message]).to include('verified successfully')
      end
      
      it 'derives key from short strings' do
        allow(config).to receive(:encryption_key).and_return('short_key')
        
        encryption = described_class.new(logger, config)
        result = encryption.verify_key
        
        # Short strings get derived into valid keys using PBKDF2
        expect(result[:valid]).to be true
        expect(result[:message]).to include('verified successfully')
      end
      
      it 'handles various key formats gracefully' do
        # Any string that's not a valid hex or base64 format gets derived
        allow(config).to receive(:encryption_key).and_return('not-a-hex-key-123')
        
        encryption = described_class.new(logger, config)
        result = encryption.verify_key
        
        expect(result[:valid]).to be true
        expect(result[:message]).to include('verified successfully')
      end
    end
    
    context 'when encryption is disabled' do
      let(:encryption_enabled) { false }
      
      it 'returns valid for disabled encryption' do
        result = encryption.verify_key
        
        expect(result[:valid]).to be true
        expect(result[:message]).to include('disabled')
      end
    end
  end
  
  describe 'key derivation' do
    context 'with passphrase' do
      before do
        allow(config).to receive(:encryption_key).and_return(nil)
        allow(config).to receive(:encryption_passphrase).and_return('my_secure_passphrase_123')
      end
      
      it 'derives key from passphrase' do
        encryption = described_class.new(logger, config)
        info = encryption.encryption_info
        
        expect(info[:has_key]).to be true
        
        # Verify the key works
        result = encryption.verify_key
        expect(result[:valid]).to be true
      end
    end
    
    context 'with hex key' do
      before do
        allow(config).to receive(:encryption_key).and_return('0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef')
      end
      
      it 'accepts hex-encoded key' do
        encryption = described_class.new(logger, config)
        result = encryption.verify_key
        
        expect(result[:valid]).to be true
      end
    end
    
    context 'with base64 key' do
      before do
        key_data = 'base64:' + Base64.encode64(SecureRandom.random_bytes(32)).strip
        allow(config).to receive(:encryption_key).and_return(key_data)
      end
      
      it 'accepts base64-encoded key' do
        encryption = described_class.new(logger, config)
        result = encryption.verify_key
        
        expect(result[:valid]).to be true
      end
    end
  end
  
  describe '#encryption_info' do
    let(:encryption) { described_class.new(logger, config) }
    
    it 'returns comprehensive encryption information' do
      info = encryption.encryption_info
      
      expect(info).to include(
        enabled: true,
        algorithm: 'aes-256-gcm',
        key_size: 32,
        has_key: true,
        key_rotation_enabled: false
      )
    end
  end
end