# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'

# Notification system for backup events
class Baktainer::NotificationSystem
  def initialize(logger, configuration)
    @logger = logger
    @configuration = configuration
    @enabled_channels = parse_enabled_channels
    @notification_thresholds = parse_notification_thresholds
  end

  # Send notification for backup completion
  def notify_backup_completed(container_name, backup_path, file_size, duration)
    return unless should_notify?(:success)

    message_data = {
      event: 'backup_completed',
      container: container_name,
      backup_path: backup_path,
      file_size: format_bytes(file_size),
      duration: format_duration(duration),
      timestamp: Time.now.iso8601,
      status: 'success'
    }

    send_notifications(
      "✅ Backup completed: #{container_name}",
      format_success_message(message_data),
      message_data
    )
  end

  # Send notification for backup failure
  def notify_backup_failed(container_name, error_message, duration = nil)
    return unless should_notify?(:failure)

    message_data = {
      event: 'backup_failed',
      container: container_name,
      error: error_message,
      duration: duration ? format_duration(duration) : nil,
      timestamp: Time.now.iso8601,
      status: 'failed'
    }

    send_notifications(
      "❌ Backup failed: #{container_name}",
      format_failure_message(message_data),
      message_data
    )
  end

  # Send notification for low disk space
  def notify_low_disk_space(available_space, backup_dir)
    return unless should_notify?(:warning)

    message_data = {
      event: 'low_disk_space',
      available_space: format_bytes(available_space),
      backup_directory: backup_dir,
      timestamp: Time.now.iso8601,
      status: 'warning'
    }

    send_notifications(
      "⚠️ Low disk space warning",
      format_warning_message(message_data),
      message_data
    )
  end

  # Send notification for system health issues
  def notify_health_check_failed(component, error_message)
    return unless should_notify?(:health)

    message_data = {
      event: 'health_check_failed',
      component: component,
      error: error_message,
      timestamp: Time.now.iso8601,
      status: 'error'
    }

    send_notifications(
      "🚨 Health check failed: #{component}",
      format_health_message(message_data),
      message_data
    )
  end

  # Send summary notification (daily/weekly reports)
  def notify_backup_summary(summary_data)
    return unless should_notify?(:summary)

    message_data = summary_data.merge(
      event: 'backup_summary',
      timestamp: Time.now.iso8601,
      status: 'info'
    )

    send_notifications(
      "📊 Backup Summary Report",
      format_summary_message(message_data),
      message_data
    )
  end

  private

  def parse_enabled_channels
    channels = ENV['BT_NOTIFICATION_CHANNELS']&.split(',') || []
    channels.map(&:strip).map(&:downcase)
  end

  def parse_notification_thresholds
    {
      success: ENV['BT_NOTIFY_SUCCESS']&.downcase == 'true',
      failure: ENV['BT_NOTIFY_FAILURES']&.downcase != 'false', # Default to true
      warning: ENV['BT_NOTIFY_WARNINGS']&.downcase != 'false', # Default to true
      health: ENV['BT_NOTIFY_HEALTH']&.downcase != 'false',    # Default to true
      summary: ENV['BT_NOTIFY_SUMMARY']&.downcase == 'true'
    }
  end

  def should_notify?(event_type)
    return false if @enabled_channels.empty?
    @notification_thresholds[event_type]
  end

  def send_notifications(title, message, data)
    @enabled_channels.each do |channel|
      begin
        case channel
        when 'slack'
          send_slack_notification(title, message, data)
        when 'webhook'
          send_webhook_notification(title, message, data)
        when 'email'
          send_email_notification(title, message, data)
        when 'discord'
          send_discord_notification(title, message, data)
        when 'teams'
          send_teams_notification(title, message, data)
        when 'log'
          send_log_notification(title, message, data)
        else
          @logger.warn("Unknown notification channel: #{channel}")
        end
      rescue => e
        @logger.error("Failed to send notification via #{channel}: #{e.message}")
      end
    end
  end

  def send_slack_notification(title, message, data)
    webhook_url = ENV['BT_SLACK_WEBHOOK_URL']
    return @logger.warn("Slack webhook URL not configured") unless webhook_url

    payload = {
      text: title,
      attachments: [{
        color: notification_color(data[:status]),
        fields: [
          { title: "Container", value: data[:container], short: true },
          { title: "Time", value: data[:timestamp], short: true }
        ],
        text: message,
        footer: "Baktainer",
        ts: Time.now.to_i
      }]
    }

    send_webhook_request(webhook_url, payload.to_json, 'application/json')
  end

  def send_discord_notification(title, message, data)
    webhook_url = ENV['BT_DISCORD_WEBHOOK_URL']
    return @logger.warn("Discord webhook URL not configured") unless webhook_url

    payload = {
      content: title,
      embeds: [{
        title: title,
        description: message,
        color: discord_color(data[:status]),
        timestamp: data[:timestamp],
        footer: { text: "Baktainer" }
      }]
    }

    send_webhook_request(webhook_url, payload.to_json, 'application/json')
  end

  def send_teams_notification(title, message, data)
    webhook_url = ENV['BT_TEAMS_WEBHOOK_URL']
    return @logger.warn("Teams webhook URL not configured") unless webhook_url

    payload = {
      "@type" => "MessageCard",
      "@context" => "https://schema.org/extensions",
      summary: title,
      themeColor: notification_color(data[:status]),
      sections: [{
        activityTitle: title,
        activitySubtitle: data[:timestamp],
        text: message,
        facts: [
          { name: "Container", value: data[:container] },
          { name: "Status", value: data[:status] }
        ].compact
      }]
    }

    send_webhook_request(webhook_url, payload.to_json, 'application/json')
  end

  def send_webhook_notification(title, message, data)
    webhook_url = ENV['BT_WEBHOOK_URL']
    return @logger.warn("Generic webhook URL not configured") unless webhook_url

    payload = {
      service: 'baktainer',
      title: title,
      message: message,
      data: data
    }

    send_webhook_request(webhook_url, payload.to_json, 'application/json')
  end

  def send_email_notification(title, message, data)
    # This would require additional email gems like 'mail'
    # For now, log that email notifications need additional setup
    @logger.info("Email notification: #{title} - #{message}")
    @logger.warn("Email notifications require additional setup (mail gem and SMTP configuration)")
  end

  def send_log_notification(title, message, data)
    case data[:status]
    when 'success'
      @logger.info("NOTIFICATION: #{title} - #{message}")
    when 'failed', 'error'
      @logger.error("NOTIFICATION: #{title} - #{message}")
    when 'warning'
      @logger.warn("NOTIFICATION: #{title} - #{message}")
    else
      @logger.info("NOTIFICATION: #{title} - #{message}")
    end
  end

  def send_webhook_request(url, payload, content_type)
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.read_timeout = 10
    http.open_timeout = 5

    request = Net::HTTP::Post.new(uri.path)
    request['Content-Type'] = content_type
    request['User-Agent'] = 'Baktainer-Notification/1.0'
    request.body = payload

    response = http.request(request)
    
    unless response.code.to_i.between?(200, 299)
      raise "HTTP #{response.code}: #{response.body}"
    end

    @logger.debug("Notification sent successfully to #{uri.host}")
  end

  def notification_color(status)
    case status
    when 'success' then 'good'
    when 'failed', 'error' then 'danger'
    when 'warning' then 'warning'
    else 'good'
    end
  end

  def discord_color(status)
    case status
    when 'success' then 0x00ff00  # Green
    when 'failed', 'error' then 0xff0000  # Red
    when 'warning' then 0xffaa00  # Orange
    else 0x0099ff  # Blue
    end
  end

  def format_success_message(data)
    msg = "Backup completed successfully for container '#{data[:container]}'"
    msg += "\n📁 Size: #{data[:file_size]}"
    msg += "\n⏱️ Duration: #{data[:duration]}"
    msg += "\n📍 Path: #{data[:backup_path]}"
    msg
  end

  def format_failure_message(data)
    msg = "Backup failed for container '#{data[:container]}'"
    msg += "\n❌ Error: #{data[:error]}"
    msg += "\n⏱️ Duration: #{data[:duration]}" if data[:duration]
    msg
  end

  def format_warning_message(data)
    msg = "Low disk space detected"
    msg += "\n💾 Available: #{data[:available_space]}"
    msg += "\n📂 Directory: #{data[:backup_directory]}"
    msg += "\n⚠️ Consider cleaning up old backups or increasing disk space"
    msg
  end

  def format_health_message(data)
    msg = "Health check failed for component '#{data[:component]}'"
    msg += "\n🚨 Error: #{data[:error]}"
    msg += "\n🔧 Check system logs and configuration"
    msg
  end

  def format_summary_message(data)
    msg = "Backup Summary Report"
    msg += "\n📊 Total Backups: #{data[:total_backups] || 0}"
    msg += "\n✅ Successful: #{data[:successful_backups] || 0}"
    msg += "\n❌ Failed: #{data[:failed_backups] || 0}"
    msg += "\n📈 Success Rate: #{data[:success_rate] || 0}%"
    msg += "\n💾 Total Data: #{format_bytes(data[:total_data_backed_up] || 0)}"
    msg
  end

  def format_bytes(bytes)
    units = ['B', 'KB', 'MB', 'GB', 'TB']
    unit_index = 0
    size = bytes.to_f

    while size >= 1024 && unit_index < units.length - 1
      size /= 1024
      unit_index += 1
    end

    "#{size.round(2)} #{units[unit_index]}"
  end

  def format_duration(seconds)
    return "#{seconds.round(2)}s" if seconds < 60
    
    minutes = seconds / 60
    return "#{minutes.round(1)}m" if minutes < 60
    
    hours = minutes / 60
    "#{hours.round(1)}h"
  end
end