# frozen_string_literal: true

module RecordingStudioApi
  class DefaultListOrder
    CALLABLE_SORT = "default_order"
    NAMED_ORDER_KEYS = %i[name order direction].freeze
    RESERVED_SORT_NAMES = [CALLABLE_SORT, "created_at"].freeze

    attr_reader :column, :direction, :callable, :name

    def self.parse(value, recordable_type:)
      return nil if value.nil?
      return value if value.is_a?(self)

      if value.is_a?(Hash)
        normalized = value.transform_keys(&:to_sym)
        if named_order_hash?(normalized)
          parse_named(normalized, recordable_type)
        else
          parse_column(value, recordable_type)
        end
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

    def self.named_order_hash?(value)
      value.key?(:name) && value.key?(:order)
    end
    private_class_method :named_order_hash?

    def self.parse_named(value, recordable_type)
      unknown = value.keys - NAMED_ORDER_KEYS
      raise ConfigurationError, "Default order for #{recordable_type} named order only accepts name, order, and direction" if unknown.any?

      name = value[:name].to_s
      raise ConfigurationError, "Default order name is invalid for #{recordable_type}: #{name}" unless name.match?(RecordableRegistration::FIELD_NAME_PATTERN)
      raise ConfigurationError, "Default order name #{name} is reserved for #{recordable_type}" if RESERVED_SORT_NAMES.include?(name)

      direction = (value[:direction] || "asc").to_s.downcase
      raise ConfigurationError, "Default order direction must be asc or desc for #{recordable_type}" unless %w[asc desc].include?(direction)

      callable = value[:order]
      raise ConfigurationError, "Default order for #{recordable_type} must pass a callable as order" unless callable.respond_to?(:call)
      raise ConfigurationError, "Default order for #{recordable_type} must take the scoped relation and a direction" unless accepts_direction?(callable)

      new(column: nil, direction: direction.freeze, callable: callable, name: name.freeze)
    end
    private_class_method :parse_named

    def self.accepts_direction?(callable)
      positional = callable.parameters.reject { |kind,| %i[key keyreq keyrest block].include?(kind) }
      required = positional.count { |kind,| kind == :req }
      optional = positional.count { |kind,| kind == :opt }
      capacity = positional.any? { |kind,| kind == :rest } ? 2 : required + optional

      2.between?(required, capacity)
    end
    private_class_method :accepts_direction?

    def initialize(column:, direction:, callable:, name: nil)
      @column = column
      @direction = direction
      @callable = callable
      @name = name
      freeze
    end

    def column?
      !column.nil?
    end

    def callable?
      !callable.nil?
    end

    def named?
      !name.nil?
    end

    def ==(other)
      other.is_a?(self.class) &&
        column == other.column &&
        direction == other.direction &&
        name == other.name &&
        callable.equal?(other.callable)
    end
    alias eql? ==

    def as_json(*)
      return { "name" => name, "direction" => direction, "callable" => true } if named?
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

    def apply_callable(authorized, direction: nil)
      ordered = named? ? callable.call(authorized, direction || self.direction) : callable.call(authorized)
      raise ConfigurationError, "Default order must return a #{authorized.klass} relation" unless ordered.is_a?(ActiveRecord::Relation) && ordered.klass == authorized.klass

      scoped = ordered.unscope(:limit, :offset)
      ids = authorized.unscope(:order).reselect(authorized.klass.primary_key)
      scoped.where(authorized.klass.primary_key => ids).order(id: named? ? (direction || self.direction) : :asc)
    end
  end
end
