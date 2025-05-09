# frozen_string_literal: true

# Baktainer is a class responsible for managing database backups using Docker containers.
#
# It supports the following database engines: PostgreSQL, MySQL, MariaDB, and Sqlite3.
#
# @example Initialize a Baktainer instance
#   baktainer = Baktainer.new(url: 'unix:///var/run/docker.sock', ssl: true, ssl_options: {})
#
# @example Run the backup process
#   baktainer.run
#
# @!attribute [r] SUPPORTED_ENGINES
#   @return [Array<String>] The list of supported database engines.
#
# @param url [String] The Docker API URL. Defaults to 'unix:///var/run/docker.sock'.
# @param ssl [Boolean] Whether to use SSL for Docker API communication. Defaults to false.
#
# @method perform_backup
#   Starts the backup process by searching for Docker containers and performing backups.
#   Logs the process at various stages.
#
# @method run
#   Schedules and runs the backup process at a specified time.
#   If the time is invalid or not provided, defaults to 05:00.
#
# @private
# @method setup_ssl
#   Configures SSL settings for Docker API communication if SSL is enabled.
#   Uses environment variables `BT_CA`, `BT_CERT`, and `BT_KEY` for SSL certificates and keys.
module Baktainer
end

require 'docker-api'
require 'cron_calc'
require 'concurrent/executor/fixed_thread_pool'
require 'baktainer/logger'
require 'baktainer/container'
require 'baktainer/backup_command'

STDOUT.sync = true


class Baktainer::Runner
  def initialize(url: 'unix:///var/run/docker.sock', ssl: false, ssl_options: {}, threads: 5)
    @pool = Concurrent::FixedThreadPool.new(threads)
    @url = url
    @ssl = ssl
    @ssl_options = ssl_options
    Docker.url = @url
    setup_ssl
    LOGGER.level = ENV['LOG_LEVEL']&.to_sym || :info
  end

  def perform_backup
    LOGGER.info('Starting backup process.')
    LOGGER.debug('Docker Searching for containers.')
    Baktainer::Containers.find_all.each do |container|
      @pool.post do
        begin
          LOGGER.info("Backing up container #{container.name} with engine #{container.engine}.")
          container.backup
          LOGGER.info("Backup completed for container #{container.name}.")
        rescue StandardError => e
          LOGGER.error("Error backing up container #{container.name}: #{e.message}")
          LOGGER.debug(e.backtrace.join("\n"))
        end
      end
    end
  end

  def run
    run_at = ENV['BT_CRON'] || '0 0 * * *'
    begin
      @cron = CronCalc.new(run_at)
    rescue 
      LOGGER.error("Invalid cron format for BT_CRON: #{run_at}.")
    end

    loop do
      now = Time.now
      next_run = @cron.next.first
      sleep_duration = next_run - now
      LOGGER.info("Sleeping for #{sleep_duration} seconds until #{next_run}.")
      sleep(sleep_duration)
      perform_backup
    end
  end

  private

  def setup_ssl
    return unless @ssl

    @cert_store = OpenSSL::X509::Store.new
    @cerificate = OpenSSL::X509::Certificate.new(ENV['BT_CA'])
    @cert_store.add_cert(@cerificate)
    Docker.options = {
      client_cert_data: ENV['BT_CERT'],
      client_key_data: ENV['BT_KEY'],
      ssl_cert_store: @cert_store,
      scheme: 'https'
    }
  end
end
