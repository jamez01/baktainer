# frozen_string_literal: true

require 'openssl'
require 'securerandom'
require 'base64'

# Handles backup encryption and decryption using AES-256-GCM
class Baktainer::BackupEncryption
  ALGORITHM = 'aes-256-gcm'
  KEY_SIZE = 32  # 256 bits
  IV_SIZE = 12   # 96 bits for GCM
  TAG_SIZE = 16  # 128 bits

  def initialize(logger, configuration = nil)
    @logger = logger
    config = configuration || Baktainer::Configuration.new
    
    # Encryption settings
    @encryption_enabled = config.encryption_enabled?
    @encryption_key = get_encryption_key(config)
    @key_rotation_enabled = config.key_rotation_enabled?
    
    @logger.info("Backup encryption initialized: enabled=#{@encryption_enabled}, key_rotation=#{@key_rotation_enabled}")
  end

  # Encrypt a backup file
  def encrypt_file(input_path, output_path = nil)
    unless @encryption_enabled
      @logger.debug("Encryption disabled, skipping encryption for #{input_path}")
      return input_path
    end

    output_path ||= "#{input_path}.encrypted"
    
    @logger.debug("Encrypting backup file: #{input_path} -> #{output_path}")
    start_time = Time.now
    
    begin
      # Generate random IV for this encryption
      iv = SecureRandom.random_bytes(IV_SIZE)
      
      # Create cipher
      cipher = OpenSSL::Cipher.new(ALGORITHM)
      cipher.encrypt
      cipher.key = @encryption_key
      cipher.iv = iv
      
      File.open(output_path, 'wb') do |output_file|
        # Write encryption header
        write_encryption_header(output_file, iv)
        
        File.open(input_path, 'rb') do |input_file|
          # Encrypt file in chunks
          while chunk = input_file.read(64 * 1024) # 64KB chunks
            encrypted_chunk = cipher.update(chunk)
            output_file.write(encrypted_chunk)
          end
          
          # Finalize encryption and get authentication tag
          final_chunk = cipher.final
          output_file.write(final_chunk)
          
          # Write authentication tag
          tag = cipher.auth_tag
          output_file.write(tag)
        end
      end
      
      # Create metadata file
      create_encryption_metadata(output_path, input_path)
      
      # Securely delete original file
      secure_delete(input_path) if File.exist?(input_path)
      
      duration = Time.now - start_time
      encrypted_size = File.size(output_path)
      @logger.info("Encryption completed: #{File.basename(output_path)} (#{format_bytes(encrypted_size)}) in #{duration.round(2)}s")
      
      output_path
    rescue => e
      @logger.error("Encryption failed for #{input_path}: #{e.message}")
      # Clean up partial encrypted file
      File.delete(output_path) if File.exist?(output_path)
      raise Baktainer::EncryptionError, "Failed to encrypt backup: #{e.message}"
    end
  end

  # Decrypt a backup file
  def decrypt_file(input_path, output_path = nil)
    unless @encryption_enabled
      @logger.debug("Encryption disabled, cannot decrypt #{input_path}")
      raise Baktainer::EncryptionError, "Encryption is disabled"
    end

    output_path ||= input_path.sub(/\.encrypted$/, '')
    
    @logger.debug("Decrypting backup file: #{input_path} -> #{output_path}")
    start_time = Time.now
    
    begin
      File.open(input_path, 'rb') do |input_file|
        # Read encryption header
        header = read_encryption_header(input_file)
        iv = header[:iv]
        
        # Create cipher for decryption
        cipher = OpenSSL::Cipher.new(ALGORITHM)
        cipher.decrypt
        cipher.key = @encryption_key
        cipher.iv = iv
        
        File.open(output_path, 'wb') do |output_file|
          # Read all encrypted data except the tag
          file_size = File.size(input_path)
          encrypted_data_size = file_size - input_file.pos - TAG_SIZE
          
          # Decrypt file in chunks
          remaining = encrypted_data_size
          while remaining > 0
            chunk_size = [64 * 1024, remaining].min
            encrypted_chunk = input_file.read(chunk_size)
            remaining -= encrypted_chunk.bytesize
            
            decrypted_chunk = cipher.update(encrypted_chunk)
            output_file.write(decrypted_chunk)
          end
          
          # Read authentication tag
          tag = input_file.read(TAG_SIZE)
          cipher.auth_tag = tag
          
          # Finalize decryption (this verifies the tag)
          final_chunk = cipher.final
          output_file.write(final_chunk)
        end
      end
      
      duration = Time.now - start_time
      decrypted_size = File.size(output_path)
      @logger.info("Decryption completed: #{File.basename(output_path)} (#{format_bytes(decrypted_size)}) in #{duration.round(2)}s")
      
      output_path
    rescue OpenSSL::Cipher::CipherError => e
      @logger.error("Decryption failed for #{input_path}: #{e.message}")
      File.delete(output_path) if File.exist?(output_path)
      raise Baktainer::EncryptionError, "Failed to decrypt backup (authentication failed): #{e.message}"
    rescue => e
      @logger.error("Decryption failed for #{input_path}: #{e.message}")
      File.delete(output_path) if File.exist?(output_path)
      raise Baktainer::EncryptionError, "Failed to decrypt backup: #{e.message}"
    end
  end

  # Verify encryption key
  def verify_key
    unless @encryption_enabled
      return { valid: true, message: "Encryption disabled" }
    end

    unless @encryption_key
      return { valid: false, message: "No encryption key configured" }
    end

    if @encryption_key.bytesize != KEY_SIZE
      return { valid: false, message: "Invalid key size: expected #{KEY_SIZE} bytes, got #{@encryption_key.bytesize}" }
    end

    # Test encryption/decryption with sample data
    begin
      test_data = "Baktainer encryption test"
      test_file = "/tmp/baktainer_key_test_#{SecureRandom.hex(8)}"
      
      File.write(test_file, test_data)
      encrypted_file = encrypt_file(test_file, "#{test_file}.enc")
      decrypted_file = decrypt_file(encrypted_file, "#{test_file}.dec")
      
      decrypted_data = File.read(decrypted_file)
      
      # Cleanup
      [test_file, encrypted_file, decrypted_file, "#{encrypted_file}.meta"].each do |f|
        File.delete(f) if File.exist?(f)
      end
      
      if decrypted_data == test_data
        { valid: true, message: "Encryption key verified successfully" }
      else
        { valid: false, message: "Key verification failed: data corruption" }
      end
    rescue => e
      { valid: false, message: "Key verification failed: #{e.message}" }
    end
  end

  # Get encryption information
  def encryption_info
    {
      enabled: @encryption_enabled,
      algorithm: ALGORITHM,
      key_size: KEY_SIZE,
      has_key: !@encryption_key.nil?,
      key_rotation_enabled: @key_rotation_enabled
    }
  end

  private

  def get_encryption_key(config)
    return nil unless @encryption_enabled

    # Try different key sources in order of preference
    key_data = config.encryption_key ||
               config.encryption_key_file && File.exist?(config.encryption_key_file) && File.read(config.encryption_key_file) ||
               generate_key_from_passphrase(config.encryption_passphrase)

    unless key_data
      raise Baktainer::EncryptionError, "No encryption key configured. Set BT_ENCRYPTION_KEY, BT_ENCRYPTION_KEY_FILE, or BT_ENCRYPTION_PASSPHRASE"
    end

    # Handle different key formats
    if key_data.length == KEY_SIZE
      # Raw binary key
      key_data
    elsif key_data.length == KEY_SIZE * 2 && key_data.match?(/\A[0-9a-fA-F]+\z/)
      # Hex-encoded key
      decoded_key = [key_data].pack('H*')
      if decoded_key.length != KEY_SIZE
        raise Baktainer::EncryptionError, "Invalid hex key size: expected #{KEY_SIZE * 2} hex chars, got #{key_data.length}"
      end
      decoded_key
    elsif key_data.start_with?('base64:')
      # Base64-encoded key
      decoded_key = Base64.decode64(key_data[7..-1])
      if decoded_key.length != KEY_SIZE
        raise Baktainer::EncryptionError, "Invalid base64 key size: expected #{KEY_SIZE} bytes, got #{decoded_key.length}"
      end
      decoded_key
    else
      # Derive key from arbitrary string using PBKDF2
      derive_key_from_string(key_data)
    end
  end

  def generate_key_from_passphrase(passphrase)
    return nil unless passphrase && !passphrase.empty?
    
    # Use a fixed salt for consistency (in production, this should be configurable)
    salt = 'baktainer-backup-encryption-salt'
    derive_key_from_string(passphrase, salt)
  end

  def derive_key_from_string(input, salt = 'baktainer-default-salt')
    OpenSSL::PKCS5.pbkdf2_hmac(input, salt, 100000, KEY_SIZE, OpenSSL::Digest::SHA256.new)
  end

  def write_encryption_header(file, iv)
    # Write magic header
    file.write("BAKT") # Magic bytes
    file.write([1].pack('C')) # Version
    file.write([ALGORITHM.length].pack('C')) # Algorithm name length
    file.write(ALGORITHM) # Algorithm name
    file.write(iv) # Initialization vector
  end

  def read_encryption_header(file)
    # Read and verify magic header
    magic = file.read(4)
    unless magic == "BAKT"
      raise Baktainer::EncryptionError, "Invalid encrypted file format"
    end

    version = file.read(1).unpack1('C')
    unless version == 1
      raise Baktainer::EncryptionError, "Unsupported encryption version: #{version}"
    end

    algorithm_length = file.read(1).unpack1('C')
    algorithm = file.read(algorithm_length)
    unless algorithm == ALGORITHM
      raise Baktainer::EncryptionError, "Unsupported algorithm: #{algorithm}"
    end

    iv = file.read(IV_SIZE)
    
    {
      version: version,
      algorithm: algorithm,
      iv: iv
    }
  end

  def create_encryption_metadata(encrypted_path, original_path)
    metadata = {
      algorithm: ALGORITHM,
      original_file: File.basename(original_path),
      original_size: File.exist?(original_path) ? File.size(original_path) : 0,
      encrypted_size: File.size(encrypted_path),
      encrypted_at: Time.now.iso8601,
      key_fingerprint: key_fingerprint
    }
    
    metadata_path = "#{encrypted_path}.meta"
    File.write(metadata_path, metadata.to_json)
  end

  def key_fingerprint
    return nil unless @encryption_key
    Digest::SHA256.hexdigest(@encryption_key)[0..15] # First 16 chars of hash
  end

  def secure_delete(file_path)
    # Simple secure delete: overwrite with random data
    return unless File.exist?(file_path)
    
    file_size = File.size(file_path)
    File.open(file_path, 'wb') do |file|
      # Overwrite with random data
      remaining = file_size
      while remaining > 0
        chunk_size = [64 * 1024, remaining].min
        file.write(SecureRandom.random_bytes(chunk_size))
        remaining -= chunk_size
      end
      file.flush
      file.fsync
    end
    
    File.delete(file_path)
    @logger.debug("Securely deleted original file: #{file_path}")
  end

  def format_bytes(bytes)
    units = ['B', 'KB', 'MB', 'GB']
    unit_index = 0
    size = bytes.to_f
    
    while size >= 1024 && unit_index < units.length - 1
      size /= 1024
      unit_index += 1
    end
    
    "#{size.round(2)} #{units[unit_index]}"
  end
end

# Custom exception for encryption errors
class Baktainer::EncryptionError < StandardError; end