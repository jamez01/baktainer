# frozen_string_literal: true

require 'concurrent'
require 'monitor'

# Dynamic thread pool with automatic sizing and monitoring
class Baktainer::DynamicThreadPool
  include MonitorMixin
  
  attr_reader :min_threads, :max_threads, :current_size, :queue_size, :active_threads

  def initialize(min_threads: 2, max_threads: 20, initial_size: 4, logger: nil)
    super()
    @min_threads = [min_threads, 1].max
    @max_threads = [max_threads, @min_threads].max
    @current_size = [[initial_size, @min_threads].max, @max_threads].min
    @logger = logger
    
    @pool = Concurrent::FixedThreadPool.new(@current_size)
    @queue_size = 0
    @active_threads = 0
    @completed_tasks = 0
    @failed_tasks = 0
    
    @last_resize_time = Time.now
    @resize_cooldown = 30 # seconds
    
    @metrics = {
      queue_length_history: [],
      utilization_history: [],
      resize_events: []
    }
    
    start_monitoring_thread
  end

  def post(&block)
    synchronize do
      @queue_size += 1
      evaluate_pool_size
    end
    
    # Work around the Concurrent::FixedThreadPool issue by using a simpler approach
    begin
      future = @pool.post do
        begin
          synchronize { @active_threads += 1 }
          result = block.call
          synchronize { @completed_tasks += 1 }
          result
        rescue => e
          synchronize { @failed_tasks += 1 }
          @logger&.error("Thread pool task failed: #{e.message}")
          raise
        ensure
          synchronize do
            @active_threads -= 1
            @queue_size -= 1
          end
        end
      end
      
      # If we get a boolean instead of a Future, return a wrapped Future
      if future == true || future == false
        @logger&.warn("Thread pool returned boolean (#{future}), wrapping in immediate Future")
        # Create a simple Future-like object that responds to .value
        future = Concurrent::IVar.new.tap { |ivar| ivar.set(future) }
      end
      
      future
    rescue => e
      @logger&.error("Failed to post to thread pool: #{e.message}")
      # Return an immediate failed future
      Concurrent::IVar.new.tap { |ivar| ivar.fail(e) }
    end
  end

  def shutdown
    @monitoring_thread&.kill if @monitoring_thread&.alive?
    @pool.shutdown
    @pool.wait_for_termination
  end

  def statistics
    synchronize do
      {
        current_size: @current_size,
        min_threads: @min_threads,
        max_threads: @max_threads,
        queue_size: @queue_size,
        active_threads: @active_threads,
        completed_tasks: @completed_tasks,
        failed_tasks: @failed_tasks,
        utilization: utilization_percentage,
        queue_pressure: queue_pressure_percentage,
        last_resize: @last_resize_time,
        resize_events: @metrics[:resize_events].last(10)
      }
    end
  end

  def force_resize(new_size)
    new_size = [[new_size, @min_threads].max, @max_threads].min
    
    synchronize do
      return if new_size == @current_size
      
      old_size = @current_size
      resize_pool(new_size, :manual)
      
      @logger&.info("Thread pool manually resized from #{old_size} to #{@current_size}")
    end
  end

  private

  def start_monitoring_thread
    @monitoring_thread = Thread.new do
      loop do
        sleep(10) # Check every 10 seconds
        
        begin
          synchronize do
            record_metrics
            evaluate_pool_size
          end
        rescue => e
          @logger&.error("Thread pool monitoring error: #{e.message}")
        end
      end
    end
  end

  def evaluate_pool_size
    return if resize_cooldown_active?
    
    utilization = utilization_percentage
    queue_pressure = queue_pressure_percentage
    
    # Scale up conditions
    if should_scale_up?(utilization, queue_pressure)
      scale_up
    # Scale down conditions  
    elsif should_scale_down?(utilization, queue_pressure)
      scale_down
    end
  end

  def should_scale_up?(utilization, queue_pressure)
    return false if @current_size >= @max_threads
    
    # Scale up if utilization is high or queue is building up
    (utilization > 80 || queue_pressure > 50) && @queue_size > 0
  end

  def should_scale_down?(utilization, queue_pressure)
    return false if @current_size <= @min_threads
    
    # Scale down if utilization is low and queue is empty
    utilization < 30 && queue_pressure == 0 && @queue_size == 0
  end

  def scale_up
    new_size = [@current_size + 1, @max_threads].min
    return if new_size == @current_size
    
    resize_pool(new_size, :scale_up)
    @logger&.info("Thread pool scaled up to #{@current_size} threads (utilization: #{utilization_percentage}%, queue: #{@queue_size})")
  end

  def scale_down
    new_size = [@current_size - 1, @min_threads].max
    return if new_size == @current_size
    
    resize_pool(new_size, :scale_down)
    @logger&.info("Thread pool scaled down to #{@current_size} threads (utilization: #{utilization_percentage}%, queue: #{@queue_size})")
  end

  def resize_pool(new_size, reason)
    old_pool = @pool
    @pool = Concurrent::FixedThreadPool.new(new_size)
    
    # Record resize event
    @metrics[:resize_events] << {
      timestamp: Time.now.iso8601,
      old_size: @current_size,
      new_size: new_size,
      reason: reason,
      utilization: utilization_percentage,
      queue_size: @queue_size
    }
    
    @current_size = new_size
    @last_resize_time = Time.now
    
    # Shutdown old pool gracefully
    Thread.new do
      old_pool.shutdown
      old_pool.wait_for_termination(5)
    end
  end

  def resize_cooldown_active?
    Time.now - @last_resize_time < @resize_cooldown
  end

  def utilization_percentage
    return 0 if @current_size == 0
    (@active_threads.to_f / @current_size * 100).round(2)
  end

  def queue_pressure_percentage
    return 0 if @current_size == 0
    # Queue pressure relative to thread pool size
    ([@queue_size.to_f / @current_size, 1.0].min * 100).round(2)
  end

  def record_metrics
    @metrics[:queue_length_history] << @queue_size
    @metrics[:utilization_history] << utilization_percentage
    
    # Keep only last 100 readings
    @metrics[:queue_length_history].shift if @metrics[:queue_length_history].size > 100
    @metrics[:utilization_history].shift if @metrics[:utilization_history].size > 100
  end
end