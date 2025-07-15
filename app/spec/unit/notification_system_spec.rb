# frozen_string_literal: true

require 'spec_helper'
require 'baktainer/notification_system'
require 'webmock/rspec'

RSpec.describe Baktainer::NotificationSystem do
  let(:logger) { double('Logger', info: nil, debug: nil, warn: nil, error: nil) }
  let(:configuration) { double('Configuration') }
  let(:notification_system) { described_class.new(logger, configuration) }

  before do
    # Mock environment variables
    stub_const('ENV', ENV.to_hash.merge(
      'BT_NOTIFICATION_CHANNELS' => 'log,webhook',
      'BT_NOTIFY_FAILURES' => 'true',
      'BT_NOTIFY_SUCCESS' => 'false',
      'BT_WEBHOOK_URL' => 'https://example.com/webhook'
    ))
  end

  describe '#notify_backup_completed' do
    context 'when success notifications are disabled' do
      it 'does not send notification' do
        expect(logger).not_to receive(:info).with(/NOTIFICATION/)
        notification_system.notify_backup_completed('test-app', '/path/to/backup.sql', 1024, 30.5)
      end
    end

    context 'when success notifications are enabled' do
      before do
        stub_const('ENV', ENV.to_hash.merge(
          'BT_NOTIFICATION_CHANNELS' => 'log',
          'BT_NOTIFY_SUCCESS' => 'true'
        ))
      end

      it 'sends log notification' do
        expect(logger).to receive(:info).with(/NOTIFICATION.*Backup completed/)
        notification_system.notify_backup_completed('test-app', '/path/to/backup.sql', 1024, 30.5)
      end
    end
  end

  describe '#notify_backup_failed' do
    before do
      stub_request(:post, "https://example.com/webhook")
        .to_return(status: 200, body: "", headers: {})
    end

    it 'sends failure notification' do
      expect(logger).to receive(:error).with(/NOTIFICATION.*Backup failed/)
      notification_system.notify_backup_failed('test-app', 'Connection timeout')
    end
  end

  describe '#notify_low_disk_space' do
    before do
      stub_request(:post, "https://example.com/webhook")
        .to_return(status: 200, body: "", headers: {})
    end

    it 'sends warning notification' do
      expect(logger).to receive(:warn).with(/NOTIFICATION.*Low disk space/)
      notification_system.notify_low_disk_space(100 * 1024 * 1024, '/backups')
    end
  end

  describe '#notify_health_check_failed' do
    before do
      stub_request(:post, "https://example.com/webhook")
        .to_return(status: 200, body: "", headers: {})
    end

    it 'sends error notification' do
      expect(logger).to receive(:error).with(/NOTIFICATION.*Health check failed/)
      notification_system.notify_health_check_failed('docker', 'Connection refused')
    end
  end

  describe 'webhook notifications' do
    before do
      stub_const('ENV', ENV.to_hash.merge(
        'BT_NOTIFICATION_CHANNELS' => 'webhook',
        'BT_NOTIFY_FAILURES' => 'true',
        'BT_WEBHOOK_URL' => 'https://example.com/webhook'
      ))
      
      stub_request(:post, "https://example.com/webhook")
        .to_return(status: 200, body: "", headers: {})
    end

    it 'sends webhook notification for failures' do
      expect(logger).to receive(:debug).with(/Notification sent successfully/)
      notification_system.notify_backup_failed('test-app', 'Connection error')
    end
  end

  describe 'format helpers' do
    it 'formats bytes correctly' do
      # This tests the private method indirectly through notifications
      expect(logger).to receive(:info).with(/1\.0 KB/)
      
      stub_const('ENV', ENV.to_hash.merge(
        'BT_NOTIFICATION_CHANNELS' => 'log',
        'BT_NOTIFY_SUCCESS' => 'true'
      ))
      
      notification_system.notify_backup_completed('test', '/path', 1024, 1.0)
    end

    it 'formats duration correctly' do
      expect(logger).to receive(:info).with(/1\.1m/)
      
      stub_const('ENV', ENV.to_hash.merge(
        'BT_NOTIFICATION_CHANNELS' => 'log',
        'BT_NOTIFY_SUCCESS' => 'true'
      ))
      
      notification_system.notify_backup_completed('test', '/path', 100, 65.0)
    end
  end
end