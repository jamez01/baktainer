# frozen_string_literal: true

require 'logger'
require 'json'

# Log messages in JSON format
class JsonLogger < Logger
  def format_message(severity, timestamp, progname, msg)
    {
      severity: severity,
      timestamp: timestamp,
      progname: progname || 'backtainer',
      message: msg
    }.to_json + "\n"
  end

  def initialize
    super(STDOUT) 
  end
end

LOGGER = JsonLogger.new
