# frozen_string_literal: true

require 'baktainer/backup_strategy'

# Factory for creating database backup strategies
class Baktainer::BackupStrategyFactory
  # Registry of engine types to strategy classes
  STRATEGY_REGISTRY = {
    'mysql' => Baktainer::MySQLBackupStrategy,
    'mariadb' => Baktainer::MariaDBBackupStrategy,
    'postgres' => Baktainer::PostgreSQLBackupStrategy,
    'postgresql' => Baktainer::PostgreSQLBackupStrategy,
    'sqlite' => Baktainer::SQLiteBackupStrategy,
    'mongodb' => Baktainer::MongoDBBackupStrategy
  }.freeze

  def self.create_strategy(engine, logger)
    engine_key = engine.to_s.downcase
    strategy_class = STRATEGY_REGISTRY[engine_key]
    
    unless strategy_class
      raise UnsupportedEngineError, "Unsupported database engine: #{engine}. Supported engines: #{supported_engines.join(', ')}"
    end
    
    strategy_class.new(logger)
  end

  def self.supported_engines
    STRATEGY_REGISTRY.keys
  end

  def self.supports_engine?(engine)
    STRATEGY_REGISTRY.key?(engine.to_s.downcase)
  end

  def self.register_strategy(engine, strategy_class)
    unless strategy_class <= Baktainer::BackupStrategy
      raise ArgumentError, "Strategy class must inherit from Baktainer::BackupStrategy"
    end
    
    STRATEGY_REGISTRY[engine.to_s.downcase] = strategy_class
  end
end

# Custom exception for unsupported engines
class Baktainer::UnsupportedEngineError < StandardError; end