# frozen_string_literal: true

module RecordingStudioApi
  class DefaultListOrder
    CALLABLE_SORT = "default_order"

    attr_reader :column, :direction, :callable

    def self.parse(value, recordable_type:)
      return nil if value.nil?
      return value if value.is_a?(self)

      if value.is_a?(Hash)
        parse_column(value, recordable_type)
      elsif value.respond_to?(:call)
        parse_callable(value, recordable_type)
      else
        raise ConfigurationError, "Default order for #{recordable_type} must be a column and direction or a callable"
      end
    end

    def self.parse_column(value, recordable_type)
      raise ConfigurationError, "Default order for #{recordable_type} must name one column" unless value.size == 1

      raw_column, raw_direction = value.first
      column = raw_column.to_s
      raise ConfigurationError, "Default order column is invalid for #{recordable_type}: #{column}" unless column.match?(RecordableRegistration::FIELD_NAME_PATTERN)

      direction = raw_direction.to_s.downcase
      raise ConfigurationError, "Default order direction must be asc or desc for #{recordable_type}" unless %w[asc desc].include?(direction)

      order = new(column: column.freeze, direction: direction.freeze, callable: nil)
      order.ensure_known_column!(recordable_type)
      order
    end
    private_class_method :parse_column

    def self.parse_callable(value, recordable_type)
      required = value.arity.negative? ? (-value.arity - 1) : value.arity
      raise ConfigurationError, "Default order for #{recordable_type} must take the scoped relation" if value.arity.zero? || required > 1

      new(column: nil, direction: nil, callable: value)
    end
    private_class_method :parse_callable

    def initialize(column:, direction:, callable:)
      @column = column
      @direction = direction
      @callable = callable
      freeze
    end

    def column?
      !column.nil?
    end

    def callable?
      !callable.nil?
    end

    def ==(other)
      other.is_a?(self.class) && column == other.column && direction == other.direction && callable.equal?(other.callable)
    end
    alias eql? ==

    def as_json(*)
      return { "callable" => true } if callable?

      { "column" => column, "direction" => direction }
    end

    def recording_column?(recording_class)
      recording_class.column_names.include?(column)
    end

    def ensure_column!(recordable_class, recording_class)
      return if recording_column?(recording_class)
      return if recordable_class.column_names.include?(column)

      raise ConfigurationError, "Default order column #{column} is not on #{recordable_class} or #{recording_class}"
    end

    def ensure_known_column!(recordable_type)
      recordable = recordable_type.to_s.safe_constantize
      recording = defined?(RecordingStudio::Recording) ? RecordingStudio::Recording : nil
      return unless recordable.respond_to?(:column_names) && recording.respond_to?(:column_names)

      ensure_column!(recordable, recording)
    rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::NoDatabaseError
      nil
    end

    def apply_callable(authorized)
      ordered = callable.call(authorized)
      raise ConfigurationError, "Default order must return a #{authorized.klass} relation" unless ordered.is_a?(ActiveRecord::Relation) && ordered.klass == authorized.klass

      scoped = ordered.unscope(:limit, :offset)
      ids = authorized.unscope(:order).reselect(authorized.klass.primary_key)
      scoped.where(authorized.klass.primary_key => ids).order(id: :asc)
    end
  end
end
