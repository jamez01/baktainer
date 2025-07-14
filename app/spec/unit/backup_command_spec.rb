# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Baktainer::BackupCommand do
  let(:backup_command) { described_class.new }

  describe '#mysql' do
    it 'generates correct mysqldump command' do
      result = backup_command.mysql(login: 'user', password: 'pass', database: 'testdb')
      
      expect(result).to be_a(Hash)
      expect(result[:env]).to eq([])
      expect(result[:cmd]).to eq(['mysqldump', '-u', 'user', '-ppass', 'testdb'])
    end

    it 'handles nil parameters' do
      expect {
        backup_command.mysql(login: nil, password: nil, database: nil)
      }.not_to raise_error
    end
  end

  describe '#mariadb' do
    it 'generates correct mysqldump command for MariaDB' do
      result = backup_command.mariadb(login: 'user', password: 'pass', database: 'testdb')
      
      expect(result).to be_a(Hash)
      expect(result[:env]).to eq([])
      expect(result[:cmd]).to eq(['mysqldump', '-u', 'user', '-ppass', 'testdb'])
    end
  end

  describe '#postgres' do
    it 'generates correct pg_dump command' do
      result = backup_command.postgres(login: 'user', password: 'pass', database: 'testdb')
      
      expect(result).to be_a(Hash)
      expect(result[:env]).to eq(['PGPASSWORD=pass'])
      expect(result[:cmd]).to eq(['pg_dump', '-U', 'user', '-d', 'testdb'])
    end

    it 'generates correct pg_dumpall command when all is true' do
      result = backup_command.postgres(login: 'user', password: 'pass', database: 'testdb', all: true)
      
      expect(result[:env]).to eq(['PGPASSWORD=pass'])
      expect(result[:cmd]).to eq(['pg_dumpall', '-U', 'user'])
    end
  end

  describe '#postgres_all' do
    it 'calls postgres with all: true' do
      expect(backup_command).to receive(:postgres).with(
        login: 'postgres',
        password: 'pass',
        database: 'testdb',
        all: true
      )
      
      backup_command.postgres_all(login: 'postgres', password: 'pass', database: 'testdb')
    end
  end

  describe '#sqlite' do
    it 'generates correct sqlite3 command' do
      result = backup_command.sqlite(database: '/path/to/test.db')
      
      expect(result).to be_a(Hash)
      expect(result[:env]).to eq([])
      expect(result[:cmd]).to eq(['sqlite3', '/path/to/test.db', '.dump'])
    end

    it 'handles missing database parameter' do
      result = backup_command.sqlite(database: nil)
      
      expect(result[:cmd]).to eq(['sqlite3', nil, '.dump'])
    end
  end

  describe '#custom' do
    it 'splits custom command string' do
      result = backup_command.custom(command: 'pg_dump -U user testdb')
      
      expect(result).to be_a(Hash)
      expect(result[:env]).to eq([])
      expect(result[:cmd]).to eq(['pg_dump', '-U', 'user', 'testdb'])
    end

    it 'handles nil command' do
      expect {
        backup_command.custom(command: nil)
      }.to raise_error(NoMethodError)
    end

    it 'handles empty command' do
      result = backup_command.custom(command: '')
      
      expect(result[:cmd]).to eq([])
    end

    it 'handles commands with multiple spaces' do
      result = backup_command.custom(command: 'pg_dump  -U   user    testdb')
      
      expect(result[:cmd]).to eq(['pg_dump', '-U', 'user', 'testdb'])
    end
  end
end