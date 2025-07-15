# frozen_string_literal: true

# Simple thread pool implementation that works reliably for our use case
class SimpleThreadPool
  def initialize(thread_count = 4)
    @thread_count = thread_count
    @queue = Queue.new
    @threads = []
    @shutdown = false
    
    # Start worker threads
    @thread_count.times do
      @threads << Thread.new { worker_loop }
    end
  end

  def post(&block)
    return SimpleFuture.failed(StandardError.new("Thread pool is shut down")) if @shutdown
    
    future = SimpleFuture.new
    @queue << { block: block, future: future }
    future
  end

  def shutdown
    @shutdown = true
    @thread_count.times { @queue << :shutdown }
    @threads.each(&:join)
  end

  def kill
    @shutdown = true
    @threads.each(&:kill)
  end

  private

  def worker_loop
    while (item = @queue.pop)
      break if item == :shutdown
      
      begin
        result = item[:block].call
        item[:future].set(result)
      rescue => e
        item[:future].fail(e)
      end
    end
  end
end

# Simple Future implementation
class SimpleFuture
  def initialize
    @mutex = Mutex.new
    @condition = ConditionVariable.new
    @completed = false
    @value = nil
    @error = nil
  end

  def set(value)
    @mutex.synchronize do
      return if @completed
      @value = value
      @completed = true
      @condition.broadcast
    end
  end

  def fail(error)
    @mutex.synchronize do
      return if @completed
      @error = error
      @completed = true
      @condition.broadcast
    end
  end

  def value
    @mutex.synchronize do
      @condition.wait(@mutex) until @completed
      raise @error if @error
      @value
    end
  end

  def self.failed(error)
    future = new
    future.fail(error)
    future
  end
end