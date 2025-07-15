# frozen_string_literal: true

require 'zlib'
require 'digest'

# Memory-optimized streaming backup handler for large databases
class Baktainer::StreamingBackupHandler
  # Buffer size for streaming operations (64KB)
  BUFFER_SIZE = 64 * 1024
  
  # Memory limit for backup operations (256MB)
  MEMORY_LIMIT = 256 * 1024 * 1024

  def initialize(logger)
    @logger = logger
    @memory_monitor = MemoryMonitor.new(logger)
  end

  def stream_backup(container, command, output_path, compress: true)
    @logger.debug("Starting streaming backup to #{output_path}")
    
    total_bytes = 0
    start_time = Time.now
    
    begin
      if compress
        stream_compressed_backup(container, command, output_path) do |bytes_written|
          total_bytes += bytes_written
          @memory_monitor.check_memory_usage
          yield(bytes_written) if block_given?
        end
      else
        stream_uncompressed_backup(container, command, output_path) do |bytes_written|
          total_bytes += bytes_written
          @memory_monitor.check_memory_usage
          yield(bytes_written) if block_given?
        end
      end
      
      duration = Time.now - start_time
      @logger.info("Streaming backup completed: #{total_bytes} bytes in #{duration.round(2)}s")
      
      total_bytes
    rescue => e
      @logger.error("Streaming backup failed: #{e.message}")
      File.delete(output_path) if File.exist?(output_path)
      raise
    end
  end

  private

  def stream_compressed_backup(container, command, output_path)
    File.open(output_path, 'wb') do |file|
      gz_writer = Zlib::GzipWriter.new(file)
      
      begin
        bytes_written = stream_docker_exec(container, command) do |chunk|
          gz_writer.write(chunk)
          yield(chunk.bytesize) if block_given?
        end
        
        gz_writer.finish
        bytes_written
      ensure
        gz_writer.close
      end
    end
  end

  def stream_uncompressed_backup(container, command, output_path)
    File.open(output_path, 'wb') do |file|
      stream_docker_exec(container, command) do |chunk|
        file.write(chunk)
        file.flush if chunk.bytesize > BUFFER_SIZE
        yield(chunk.bytesize) if block_given?
      end
    end
  end

  def stream_docker_exec(container, command)
    stderr_buffer = StringIO.new
    total_bytes = 0
    
    container.exec(command[:cmd], env: command[:env]) do |stream, chunk|
      case stream
      when :stdout
        total_bytes += chunk.bytesize
        yield(chunk) if block_given?
      when :stderr
        stderr_buffer.write(chunk)
        
        # Log stderr in chunks to avoid memory buildup
        if stderr_buffer.size > BUFFER_SIZE
          @logger.warn("Backup stderr: #{stderr_buffer.string}")
          stderr_buffer.rewind
          stderr_buffer.truncate(0)
        end
      end
    end
    
    # Log any remaining stderr
    if stderr_buffer.size > 0
      @logger.warn("Backup stderr: #{stderr_buffer.string}")
    end
    
    total_bytes
  rescue Docker::Error::TimeoutError => e
    raise StandardError, "Docker command timed out: #{e.message}"
  rescue Docker::Error::DockerError => e
    raise StandardError, "Docker execution failed: #{e.message}"
  ensure
    stderr_buffer.close if stderr_buffer
  end

  # Memory monitoring helper class
  class MemoryMonitor
    def initialize(logger)
      @logger = logger
      @last_check = Time.now
      @check_interval = 5 # seconds
    end

    def check_memory_usage
      return unless should_check_memory?
      
      current_memory = get_memory_usage
      if current_memory > MEMORY_LIMIT
        @logger.warn("Memory usage high: #{format_bytes(current_memory)}")
        
        # Force garbage collection
        GC.start
        
        # Check again after GC
        after_gc_memory = get_memory_usage
        if after_gc_memory > MEMORY_LIMIT
          raise MemoryLimitError, "Memory limit exceeded: #{format_bytes(after_gc_memory)}"
        end
        
        @logger.debug("Memory usage after GC: #{format_bytes(after_gc_memory)}")
      end
      
      @last_check = Time.now
    end

    private

    def should_check_memory?
      Time.now - @last_check > @check_interval
    end

    def get_memory_usage
      # Get RSS (Resident Set Size) in bytes
      if File.exist?('/proc/self/status')
        # Linux
        status = File.read('/proc/self/status')
        if match = status.match(/VmRSS:\s+(\d+)\s+kB/)
          return match[1].to_i * 1024
        end
      end
      
      # Fallback: use Ruby's built-in memory reporting
      GC.stat[:heap_allocated_pages] * GC.stat[:heap_page_size]
    rescue
      # If we can't get memory usage, return 0 to avoid blocking
      0
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
end

# Custom exception for memory limit exceeded
class Baktainer::MemoryLimitError < StandardError; end