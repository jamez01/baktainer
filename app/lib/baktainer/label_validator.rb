# frozen_string_literal: true

# Schema validation for Docker container labels
class Baktainer::LabelValidator
  SUPPORTED_ENGINES = %w[mysql mariadb postgres postgresql sqlite].freeze
  
  # Schema definition for backup labels
  LABEL_SCHEMA = {
    'baktainer.backup' => {
      required: true,
      type: :boolean,
      description: 'Enable backup for this container'
    },
    'baktainer.db.engine' => {
      required: true,
      type: :string,
      enum: SUPPORTED_ENGINES,
      description: 'Database engine type'
    },
    'baktainer.db.name' => {
      required: true,
      type: :string,
      min_length: 1,
      max_length: 64,
      pattern: /^[a-zA-Z0-9_-]+$/,
      description: 'Database name to backup'
    },
    'baktainer.db.user' => {
      required: true,
      type: :string,
      min_length: 1,
      max_length: 64,
      description: 'Database username (not required for SQLite)',
      conditional: ->(labels) { labels['baktainer.db.engine'] != 'sqlite' }
    },
    'baktainer.db.password' => {
      required: true,
      type: :string,
      min_length: 1,
      description: 'Database password (not required for SQLite)',
      conditional: ->(labels) { labels['baktainer.db.engine'] != 'sqlite' }
    },
    'baktainer.name' => {
      required: false,
      type: :string,
      min_length: 1,
      max_length: 64,
      pattern: /^[a-zA-Z0-9_-]+$/,
      default: ->(labels) { extract_container_name_from_labels(labels) },
      description: 'Custom name for backup files (optional)'
    },
    'baktainer.db.all' => {
      required: false,
      type: :boolean,
      default: false,
      description: 'Backup all databases (MySQL/PostgreSQL only)'
    },
    'baktainer.backup.compress' => {
      required: false,
      type: :boolean,
      default: false,
      description: 'Enable gzip compression for backup files'
    },
    'baktainer.backup.encrypt' => {
      required: false,
      type: :boolean,
      default: false,
      description: 'Enable encryption for backup files'
    },
    'baktainer.backup.retention.days' => {
      required: false,
      type: :integer,
      min_value: 1,
      max_value: 3650,
      default: 30,
      description: 'Retention period in days for this container'
    },
    'baktainer.backup.retention.count' => {
      required: false,
      type: :integer,
      min_value: 0,
      max_value: 1000,
      default: 0,
      description: 'Maximum number of backups to keep (0 = unlimited)'
    },
    'baktainer.backup.priority' => {
      required: false,
      type: :string,
      enum: %w[low normal high critical],
      default: 'normal',
      description: 'Backup priority for scheduling'
    }
  }.freeze

  def initialize(logger)
    @logger = logger
    @errors = []
    @warnings = []
  end

  # Validate container labels against schema
  def validate(labels)
    reset_validation_state
    
    # Convert string values to appropriate types
    normalized_labels = normalize_labels(labels)
    
    # Validate each label against schema
    LABEL_SCHEMA.each do |label_key, schema|
      validate_label(label_key, normalized_labels[label_key], schema, normalized_labels)
    end
    
    # Check for unknown labels
    check_unknown_labels(normalized_labels)
    
    # Perform cross-field validation
    validate_cross_field_constraints(normalized_labels)
    
    {
      valid: @errors.empty?,
      errors: @errors,
      warnings: @warnings,
      normalized_labels: normalized_labels
    }
  end

  # Get detailed help for a specific label
  def get_label_help(label_key)
    schema = LABEL_SCHEMA[label_key]
    return nil unless schema

    help_text = ["#{label_key}:"]
    help_text << "  Description: #{schema[:description]}"
    help_text << "  Required: #{schema[:required] ? 'Yes' : 'No'}"
    help_text << "  Type: #{schema[:type]}"
    
    if schema[:enum]
      help_text << "  Allowed values: #{schema[:enum].join(', ')}"
    end
    
    if schema[:pattern]
      help_text << "  Pattern: #{schema[:pattern].inspect}"
    end
    
    if schema[:min_length] || schema[:max_length]
      help_text << "  Length: #{schema[:min_length] || 0}-#{schema[:max_length] || 'unlimited'} characters"
    end
    
    if schema[:min_value] || schema[:max_value]
      help_text << "  Range: #{schema[:min_value] || 'unlimited'}-#{schema[:max_value] || 'unlimited'}"
    end
    
    if schema[:default]
      default_val = schema[:default].is_a?(Proc) ? 'computed' : schema[:default]
      help_text << "  Default: #{default_val}"
    end

    help_text.join("\n")
  end

  # Get all available labels with help
  def get_all_labels_help
    LABEL_SCHEMA.keys.map { |label| get_label_help(label) }.join("\n\n")
  end

  # Validate a single label value
  def validate_single_label(label_key, value)
    reset_validation_state
    schema = LABEL_SCHEMA[label_key]
    
    if schema.nil?
      @warnings << "Unknown label: #{label_key}"
      return { valid: true, warnings: @warnings }
    end
    
    validate_label(label_key, value, schema, { label_key => value })
    
    {
      valid: @errors.empty?,
      errors: @errors,
      warnings: @warnings
    }
  end

  # Generate example labels for a given engine
  def generate_example_labels(engine)
    base_labels = {
      'baktainer.backup' => 'true',
      'baktainer.db.engine' => engine,
      'baktainer.db.name' => 'myapp_production',
      'baktainer.name' => 'myapp'
    }

    unless engine == 'sqlite'
      base_labels['baktainer.db.user'] = 'backup_user'
      base_labels['baktainer.db.password'] = 'secure_password'
    end

    # Add optional labels with examples
    base_labels['baktainer.backup.compress'] = 'true'
    base_labels['baktainer.backup.retention.days'] = '14'
    base_labels['baktainer.backup.priority'] = 'high'

    base_labels
  end

  private

  def reset_validation_state
    @errors = []
    @warnings = []
  end

  def normalize_labels(labels)
    normalized = {}
    
    labels.each do |key, value|
      schema = LABEL_SCHEMA[key]
      next unless value && !value.empty?
      
      if schema
        normalized[key] = convert_value(value, schema[:type])
      else
        normalized[key] = value  # Keep unknown labels as-is
      end
    end
    
    # Apply defaults
    LABEL_SCHEMA.each do |label_key, schema|
      next if normalized.key?(label_key)
      next unless schema[:default]
      
      if schema[:default].is_a?(Proc)
        normalized[label_key] = schema[:default].call(normalized)
      else
        normalized[label_key] = schema[:default]
      end
    end
    
    normalized
  end

  def convert_value(value, type)
    case type
    when :boolean
      case value.to_s.downcase
      when 'true', '1', 'yes', 'on' then true
      when 'false', '0', 'no', 'off' then false
      else
        raise ArgumentError, "Invalid boolean value: #{value}"
      end
    when :integer
      Integer(value)
    when :string
      value.to_s
    else
      value
    end
  rescue ArgumentError => e
    @errors << "Invalid #{type} value for label: #{e.message}"
    value
  end

  def validate_label(label_key, value, schema, all_labels)
    # Check conditional requirements
    if schema[:conditional] && !schema[:conditional].call(all_labels)
      return  # Skip validation if condition not met
    end
    
    # Check required fields
    if schema[:required] && (value.nil? || (value.is_a?(String) && value.empty?))
      @errors << "Required label missing: #{label_key} - #{schema[:description]}"
      return
    end
    
    return if value.nil?  # Skip further validation for optional empty fields
    
    # Type validation is handled in normalization
    
    # Enum validation
    if schema[:enum] && !schema[:enum].include?(value)
      @errors << "Invalid value '#{value}' for #{label_key}. Allowed: #{schema[:enum].join(', ')}"
    end
    
    # String validations
    if schema[:type] == :string && value.is_a?(String)
      if schema[:min_length] && value.length < schema[:min_length]
        @errors << "#{label_key} too short (minimum #{schema[:min_length]} characters)"
      end
      
      if schema[:max_length] && value.length > schema[:max_length]
        @errors << "#{label_key} too long (maximum #{schema[:max_length]} characters)"
      end
      
      if schema[:pattern] && !value.match?(schema[:pattern])
        @errors << "#{label_key} format invalid. Use only letters, numbers, underscores, and hyphens"
      end
    end
    
    # Integer validations
    if schema[:type] == :integer && value.is_a?(Integer)
      if schema[:min_value] && value < schema[:min_value]
        @errors << "#{label_key} too small (minimum #{schema[:min_value]})"
      end
      
      if schema[:max_value] && value > schema[:max_value]
        @errors << "#{label_key} too large (maximum #{schema[:max_value]})"
      end
    end
  end

  def check_unknown_labels(labels)
    labels.keys.each do |label_key|
      next if LABEL_SCHEMA.key?(label_key)
      next unless label_key.start_with?('baktainer.')
      
      @warnings << "Unknown baktainer label: #{label_key}. Check for typos or see documentation."
    end
  end

  def validate_cross_field_constraints(labels)
    engine = labels['baktainer.db.engine']
    
    # SQLite-specific validations
    if engine == 'sqlite'
      if labels['baktainer.db.user']
        @warnings << "baktainer.db.user not needed for SQLite engine"
      end
      
      if labels['baktainer.db.password']
        @warnings << "baktainer.db.password not needed for SQLite engine"
      end
      
      if labels['baktainer.db.all']
        @warnings << "baktainer.db.all not applicable for SQLite engine"
      end
    end
    
    # MySQL/PostgreSQL validations
    if %w[mysql mariadb postgres postgresql].include?(engine)
      if labels['baktainer.db.all'] && labels['baktainer.db.name'] != '*'
        @warnings << "When using baktainer.db.all=true, consider setting baktainer.db.name='*' for clarity"
      end
    end
    
    # Retention policy warnings
    if labels['baktainer.backup.retention.days'] && labels['baktainer.backup.retention.days'] < 7
      @warnings << "Retention period less than 7 days may result in frequent data loss"
    end
    
    # Encryption warnings
    if labels['baktainer.backup.encrypt'] && !ENV['BT_ENCRYPTION_KEY']
      @errors << "Encryption enabled but BT_ENCRYPTION_KEY environment variable not set"
    end
  end

  def self.extract_container_name_from_labels(labels)
    # This would typically extract from container name or use a default
    'backup'
  end
end