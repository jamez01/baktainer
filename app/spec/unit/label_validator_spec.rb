# frozen_string_literal: true

require 'spec_helper'
require 'baktainer/label_validator'

RSpec.describe Baktainer::LabelValidator do
  let(:logger) { double('Logger', debug: nil, info: nil, warn: nil, error: nil) }
  let(:validator) { described_class.new(logger) }

  describe '#validate' do
    context 'with valid MySQL labels' do
      let(:labels) do
        {
          'baktainer.backup' => 'true',
          'baktainer.db.engine' => 'mysql',
          'baktainer.db.name' => 'myapp_production',
          'baktainer.db.user' => 'backup_user',
          'baktainer.db.password' => 'secure_password'
        }
      end

      it 'returns valid result' do
        result = validator.validate(labels)
        expect(result[:valid]).to be true
        expect(result[:errors]).to be_empty
      end

      it 'normalizes boolean values' do
        result = validator.validate(labels)
        expect(result[:normalized_labels]['baktainer.backup']).to be true
      end
    end

    context 'with valid SQLite labels' do
      let(:labels) do
        {
          'baktainer.backup' => 'true',
          'baktainer.db.engine' => 'sqlite',
          'baktainer.db.name' => 'app_db'
        }
      end

      it 'returns valid result without auth requirements' do
        result = validator.validate(labels)
        if !result[:valid]
          puts "Validation errors: #{result[:errors]}"
          puts "Validation warnings: #{result[:warnings]}"
        end
        expect(result[:valid]).to be true
      end
    end

    context 'with missing required labels' do
      let(:labels) do
        {
          'baktainer.backup' => 'true'
          # Missing engine and name
        }
      end

      it 'returns invalid result with errors' do
        result = validator.validate(labels)
        expect(result[:valid]).to be false
        expect(result[:errors]).to include(match(/baktainer.db.engine/))
        expect(result[:errors]).to include(match(/baktainer.db.name/))
      end
    end

    context 'with invalid engine' do
      let(:labels) do
        {
          'baktainer.backup' => 'true',
          'baktainer.db.engine' => 'invalid_engine',
          'baktainer.db.name' => 'mydb'
        }
      end

      it 'returns invalid result' do
        result = validator.validate(labels)
        expect(result[:valid]).to be false
        expect(result[:errors]).to include(match(/Invalid value.*invalid_engine/))
      end
    end

    context 'with invalid database name format' do
      let(:labels) do
        {
          'baktainer.backup' => 'true',
          'baktainer.db.engine' => 'mysql',
          'baktainer.db.name' => 'invalid name with spaces!',
          'baktainer.db.user' => 'user',
          'baktainer.db.password' => 'pass'
        }
      end

      it 'returns invalid result' do
        result = validator.validate(labels)
        expect(result[:valid]).to be false
        expect(result[:errors]).to include(match(/format invalid/))
      end
    end

    context 'with unknown labels' do
      let(:labels) do
        {
          'baktainer.backup' => 'true',
          'baktainer.db.engine' => 'mysql',
          'baktainer.db.name' => 'mydb',
          'baktainer.db.user' => 'user',
          'baktainer.db.password' => 'pass',
          'baktainer.unknown.label' => 'value'
        }
      end

      it 'includes warnings for unknown labels' do
        result = validator.validate(labels)
        expect(result[:valid]).to be true
        expect(result[:warnings]).to include(match(/Unknown baktainer label/))
      end
    end
  end

  describe '#get_label_help' do
    it 'returns help for known label' do
      help = validator.get_label_help('baktainer.db.engine')
      expect(help).to include('Database engine type')
      expect(help).to include('Required: Yes')
      expect(help).to include('mysql, mariadb, postgres')
    end

    it 'returns nil for unknown label' do
      help = validator.get_label_help('unknown.label')
      expect(help).to be_nil
    end
  end

  describe '#generate_example_labels' do
    it 'generates valid MySQL example' do
      labels = validator.generate_example_labels('mysql')
      expect(labels['baktainer.db.engine']).to eq('mysql')
      expect(labels['baktainer.db.user']).not_to be_nil
      expect(labels['baktainer.db.password']).not_to be_nil
    end

    it 'generates valid SQLite example without auth' do
      labels = validator.generate_example_labels('sqlite')
      expect(labels['baktainer.db.engine']).to eq('sqlite')
      expect(labels).not_to have_key('baktainer.db.user')
      expect(labels).not_to have_key('baktainer.db.password')
    end
  end

  describe '#validate_single_label' do
    it 'validates individual label' do
      result = validator.validate_single_label('baktainer.db.engine', 'mysql')
      expect(result[:valid]).to be true
    end

    it 'detects invalid individual label' do
      result = validator.validate_single_label('baktainer.db.engine', 'invalid')
      expect(result[:valid]).to be false
    end
  end
end