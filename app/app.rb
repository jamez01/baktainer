# frozen_string_literal: true

require 'rubygems'
$LOAD_PATH.unshift "#{File.dirname(__FILE__)}/lib"
require 'bundler/setup'
require 'baktainer'
require 'baktainer/logger'
require 'baktainer/container'
require 'baktainer/backup_command'

require 'optparse'

options = {}
OptionParser.new do |opts|
  opts.banner = 'Usage: baktainer.rb [options]'

  opts.on('-N', '--now', 'Run immediately and exit.') do
    options[:now] = true
  end
end.parse!

LOGGER.info('Starting')
baktainer = Baktainer::Runner.new(
  url: ENV['BT_DOCKER_URL'] || 'unix:///var/run/docker.sock',
  ssl: ENV['BT_SSL'] || false,
  ssl_options: {
    ca_file: ENV['BT_CA'],
    client_cert: ENV['BT_CERT'],
    client_key: ENV['BT_KEY']
  }
)

baktainer.run