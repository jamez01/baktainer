# frozen_string_literal: true

# Container validation logic extracted from Container class
class Baktainer::ContainerValidator
  REQUIRED_LABELS = %w[
    baktainer.backup
    baktainer.db.engine
    baktainer.db.name
  ].freeze

  REQUIRED_AUTH_LABELS = %w[
    baktainer.db.user
    baktainer.db.password
  ].freeze

  ENGINES_REQUIRING_AUTH = %w[mysql mariadb postgres postgresql].freeze

  def initialize(container, backup_command, label_validator = nil)
    @container = container
    @backup_command = backup_command
    @label_validator = label_validator
  end

  def validate!
    validate_container_exists
    validate_container_running
    validate_labels_exist
    
    # Use enhanced label validation if available
    if @label_validator
      validate_labels_with_schema
    else
      # Fallback to legacy validation
      validate_backup_enabled
      validate_engine_defined
      validate_authentication_labels
      validate_engine_supported
    end
    
    true
  end

  def validation_errors
    errors = []
    
    begin
      validate_container_exists
    rescue => e
      errors << e.message
    end

    begin
      validate_container_running
    rescue => e
      errors << e.message
    end

    begin
      validate_labels_exist
    rescue => e
      errors << e.message
    end

    begin
      validate_backup_enabled
    rescue => e
      errors << e.message
    end

    begin
      validate_engine_defined
    rescue => e
      errors << e.message
    end

    begin
      validate_authentication_labels
    rescue => e
      errors << e.message
    end

    begin
      validate_engine_supported
    rescue => e
      errors << e.message
    end

    errors
  end

  def valid?
    validation_errors.empty?
  end

  private

  def validate_container_exists
    raise Baktainer::ValidationError, 'Unable to parse container' if @container.nil?
  end

  def validate_container_running
    state = @container.info['State']&.[]('Status')
    if state.nil? || state != 'running'
      raise Baktainer::ValidationError, 'Container not running'
    end
  end

  def validate_labels_exist
    labels = @container.info['Labels']
    if labels.nil? || labels.empty?
      raise Baktainer::ValidationError, 'Use docker labels to define db settings'
    end
  end

  def validate_backup_enabled
    labels = @container.info['Labels']
    backup_enabled = labels['baktainer.backup']&.downcase
    
    unless backup_enabled == 'true'
      raise Baktainer::ValidationError, 'Backup not enabled for this container. Set docker label baktainer.backup=true'
    end
  end

  def validate_engine_defined
    labels = @container.info['Labels']
    engine = labels['baktainer.db.engine']&.downcase
    
    if engine.nil? || engine.empty?
      raise Baktainer::ValidationError, 'DB Engine not defined. Set docker label baktainer.db.engine'
    end
  end

  def validate_authentication_labels
    labels = @container.info['Labels']
    engine = labels['baktainer.db.engine']&.downcase
    
    return unless ENGINES_REQUIRING_AUTH.include?(engine)

    missing_auth_labels = []
    
    REQUIRED_AUTH_LABELS.each do |label|
      value = labels[label]
      if value.nil? || value.empty?
        missing_auth_labels << label
      end
    end

    unless missing_auth_labels.empty?
      raise Baktainer::ValidationError, "Missing required authentication labels for #{engine}: #{missing_auth_labels.join(', ')}"
    end
  end

  def validate_engine_supported
    labels = @container.info['Labels']
    engine = labels['baktainer.db.engine']&.downcase
    
    return if engine.nil? # Already handled by validate_engine_defined
    
    unless @backup_command.respond_to?(engine.to_sym)
      raise Baktainer::ValidationError, "Unsupported database engine: #{engine}. Supported engines: #{supported_engines.join(', ')}"
    end
  end

  def validate_labels_with_schema
    labels = @container.info['Labels'] || {}
    
    # Filter to only baktainer labels
    baktainer_labels = labels.select { |k, v| k.start_with?('baktainer.') }
    
    # Validate using schema
    validation_result = @label_validator.validate(baktainer_labels)
    
    unless validation_result[:valid]
      error_msg = "Label validation failed:\n" + validation_result[:errors].join("\n")
      if validation_result[:warnings].any?
        error_msg += "\nWarnings:\n" + validation_result[:warnings].join("\n")
      end
      raise Baktainer::ValidationError, error_msg
    end
    
    # Log warnings if present
    if validation_result[:warnings].any?
      validation_result[:warnings].each do |warning|
        # Note: This would need a logger instance passed to the constructor
        puts "Warning: #{warning}" # Temporary logging
      end
    end
  end

  def supported_engines
    @backup_command.methods.select { |m| m.to_s.match(/^(mysql|mariadb|postgres|postgresql|sqlite|mongodb)$/) }
  end
end

# Custom exception for validation errors
class Baktainer::ValidationError < StandardError; end