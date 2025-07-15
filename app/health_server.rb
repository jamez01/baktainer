#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'lib/baktainer'

# Health check server runner
class HealthServerRunner
  def initialize
    @dependency_container = Baktainer::DependencyContainer.new.configure
    @logger = @dependency_container.get(:logger)
    @health_server = @dependency_container.get(:health_check_server)
  end

  def start
    port = ENV['BT_HEALTH_PORT'] || 8080
    bind = ENV['BT_HEALTH_BIND'] || '0.0.0.0'
    
    @logger.info("Starting health check server on #{bind}:#{port}")
    @logger.info("Health endpoints available:")
    @logger.info("  GET / - Dashboard")
    @logger.info("  GET /health - Health check")
    @logger.info("  GET /status - Detailed status")
    @logger.info("  GET /backups - Backup information")
    @logger.info("  GET /containers - Container discovery")
    @logger.info("  GET /config - Configuration (sanitized)")
    @logger.info("  GET /metrics - Prometheus metrics")
    
    begin
      # Use Rack to run the Sinatra app
      require 'rack'
      require 'puma'
      
      # Start Puma server with Rack
      server = Puma::Server.new(@health_server)
      server.add_tcp_listener(bind, port.to_i)
      server.run.join
    rescue Interrupt
      @logger.info("Health check server stopped")
    rescue => e
      @logger.error("Health check server error: #{e.message}")
      raise
    end
  end
end

# Start the server if this file is run directly
if __FILE__ == $0
  server = HealthServerRunner.new
  server.start
end