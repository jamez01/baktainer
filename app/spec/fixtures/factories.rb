# frozen_string_literal: true

FactoryBot.define do
  factory :docker_container_info, class: Hash do
    initialize_with do
      {
        'Id' => '1234567890abcdef',
        'Names' => ['/test-container'],
        'State' => { 'Status' => 'running' },
        'Labels' => {
          'baktainer.backup' => 'true',
          'baktainer.db.engine' => 'postgres',
          'baktainer.db.name' => 'testdb',
          'baktainer.db.user' => 'testuser',
          'baktainer.db.password' => 'testpass',
          'baktainer.name' => 'TestApp'
        }
      }
    end

    trait :mysql do
      initialize_with do
        base_attrs = attributes.dup
        base_attrs['Labels'] = base_attrs['Labels'].merge({
          'baktainer.db.engine' => 'mysql'
        })
        base_attrs
      end
    end

    trait :postgres do
      initialize_with do
        base_attrs = attributes.dup
        base_attrs['Labels'] = base_attrs['Labels'].merge({
          'baktainer.db.engine' => 'postgres'
        })
        base_attrs
      end
    end

    trait :sqlite do
      initialize_with do
        base_attrs = attributes.dup
        base_attrs['Labels'] = base_attrs['Labels'].merge({
          'baktainer.db.engine' => 'sqlite',
          'baktainer.db.name' => '/data/test.db'
        })
        base_attrs
      end
    end

    trait :stopped do
      initialize_with do
        base_attrs = attributes.dup
        base_attrs['State'] = { 'Status' => 'exited' }
        base_attrs
      end
    end

    trait :no_backup_label do
      initialize_with do
        base_attrs = build(:docker_container_info)
        labels = base_attrs['Labels'].dup
        labels.delete('baktainer.backup')
        base_attrs['Labels'] = labels
        base_attrs
      end
    end
  end
end