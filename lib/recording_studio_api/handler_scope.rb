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

    def read_action?(http_verb:, required_role:)
      role = required_role&.to_sym
      return true if role == :view
      return false if role

      http_verb&.to_sym == :get
    end

    def assert_read_opt_out!(name:, http_verb: nil, required_role: nil, action_name: nil, api: :public)
      return if read_opt_out?(action_name: action_name, http_verb: http_verb, required_role: required_role, api: api)

      raise ConfigurationError, "owns_scoping is only allowed on a read action for #{name}"
    end

    def read_opt_out?(action_name:, http_verb:, required_role:, api:)
      resource_role_name = action_name&.to_s
      return RESOURCE_ROLES[resource_role_name] == :view if resource_role_name && RESOURCE_ROLES.key?(resource_role_name)

      if action_name.present?
        action = RecordingStudioApi.capability_action(action_name, api: api)
        return action.read_action? if action
      end

      read_action?(http_verb: http_verb, required_role: required_role)
    end
  end
end
