# frozen_string_literal: true

module RecordingStudioApi
  module HandlerScope
    RESOURCE_ROLES = {
      "index" => :view,
      "show" => :view,
      "create" => :edit,
      "update" => :edit,
      "destroy" => :edit
    }.freeze
    READ_ACTIONS = %w[index show].freeze
    TRASHED_ACTIONS = %w[restore destroy].freeze

    module_function

    def flag(value, name:)
      return false if value.nil? || value == false
      return true if value == true

      raise ConfigurationError, "#{name} must be true or false"
    end

    def resource_role(action_name)
      role = RESOURCE_ROLES[action_name.to_s]
      raise ArgumentError, "unknown resource action #{action_name}" if role.nil?

      role
    end

    def real_read?(http_verb: nil, required_role: nil, action_name: nil)
      name = action_name&.to_s
      builtin_read = name.present? && READ_ACTIONS.include?(name)
      return false unless builtin_read || http_verb&.to_sym == :get

      role = required_role&.to_sym
      return false if role && role != :view

      true
    end

    def assert_read_opt_out!(name:, http_verb: nil, required_role: nil, action_name: nil, api: :public)
      return if read_opt_out?(action_name: action_name, http_verb: http_verb, required_role: required_role, api: api)

      raise ConfigurationError, "owns_scoping is only allowed on a read action for #{name}"
    end

    def read_opt_out?(action_name:, http_verb:, required_role:, api:)
      name = action_name&.to_s
      return real_read?(action_name: name, http_verb: http_verb, required_role: required_role || resource_role(name)) if name.present? && RESOURCE_ROLES.key?(name)

      if name.present?
        action = RecordingStudioApi.capability_action(name, api: api)
        return real_read?(http_verb: action.http_verb, required_role: required_role || action.required_role, action_name: action.name) if action
      end

      real_read?(http_verb: http_verb, required_role: required_role, action_name: action_name)
    end

    def assert_include_trashed!(name:, http_verb: nil, action_name: nil, api: :public)
      return if include_trashed_allowed?(http_verb: http_verb, action_name: action_name, api: api)

      raise ConfigurationError, "include_trashed is only allowed on a read, restore, or destroy action for #{name}"
    end

    def include_trashed_allowed?(http_verb: nil, action_name: nil, api: :public)
      name = action_name&.to_s
      return true if name.present? && (READ_ACTIONS + TRASHED_ACTIONS).include?(name)
      return false if name.present? && %w[create update].include?(name)

      if http_verb.nil? && name.present?
        action = RecordingStudioApi.capability_action(name, api: api)
        return false unless action

        return include_trashed_allowed?(http_verb: action.http_verb, action_name: action.name)
      end

      %i[get delete].include?(http_verb&.to_sym)
    end

    def resource_opt_out?(owns_scoping, action_name)
      owns_scoping && real_read?(action_name: action_name, required_role: resource_role(action_name))
    end

    def endpoint_opt_out?(endpoint)
      endpoint.owns_scoping? && real_read?(http_verb: endpoint.http_verb, required_role: endpoint.authorization_role)
    end

    def dispatch_read?(action:, role:)
      real_read?(http_verb: action.http_verb, required_role: role, action_name: action.name)
    end
  end
end
