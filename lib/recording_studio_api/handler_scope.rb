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
    TRASHED_SEMANTICS = %i[restore destroy].freeze
    RESOURCE_VERBS = {
      "index" => :get,
      "show" => :get,
      "create" => :post,
      "update" => :patch,
      "destroy" => :delete
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
      return name == "update" || real_read?(action_name: name, http_verb: http_verb, required_role: required_role || resource_role(name)) if name.present? && RESOURCE_ROLES.key?(name)

      if name.present?
        action = RecordingStudioApi.capability_action(name, api: api)
        verb = action ? action.http_verb : http_verb
        role = required_role || action&.required_role
        action_name = action&.name || name
        return true if real_read?(http_verb: verb, required_role: role, action_name: action_name)

        return %i[post patch put].include?(verb&.to_sym) && (role.blank? || edit_or_higher?(role))
      end

      real_read?(http_verb: http_verb, required_role: required_role, action_name: action_name)
    end

    def trashed_semantics(value, name:)
      return if value.nil? || value == false

      semantic = value.to_sym
      return semantic if TRASHED_SEMANTICS.include?(semantic)

      raise ConfigurationError, "trashed_semantics must be :restore or :destroy for #{name}"
    rescue NoMethodError
      raise ConfigurationError, "trashed_semantics must be :restore or :destroy for #{name}"
    end

    def assert_trashed_semantics!(name:, trashed_semantics:, http_verb:, required_role:, owns_scoping:)
      return if trashed_semantics.nil?

      raise ConfigurationError, "trashed_semantics requires a registered non-GET action for #{name}" if http_verb.nil?
      raise ConfigurationError, "trashed_semantics is not allowed on a GET for #{name}" if http_verb.to_sym == :get
      raise ConfigurationError, "trashed_semantics is not allowed with owns_scoping for #{name}" if owns_scoping
      return if edit_or_higher?(required_role)

      raise ConfigurationError, "trashed_semantics requires a role of :edit or higher for #{name}"
    end

    def assert_include_trashed!(name:, http_verb: nil, action_name: nil, api: :public, trashed_semantics: nil)
      return if include_trashed_allowed?(http_verb: http_verb, action_name: action_name, api: api, trashed_semantics: trashed_semantics)

      raise ConfigurationError, "include_trashed is only allowed on a read, restore, or destroy action for #{name}"
    end

    def include_trashed_allowed?(http_verb: nil, action_name: nil, api: :public, trashed_semantics: nil)
      return true if TRASHED_SEMANTICS.include?(trashed_semantics&.to_sym)

      name = action_name&.to_s
      return true if name.present? && (READ_ACTIONS + TRASHED_ACTIONS).include?(name)
      return false if name.present? && %w[create update].include?(name)

      if http_verb.nil? && name.present?
        action = RecordingStudioApi.capability_action(name, api: api)
        return false unless action

        return include_trashed_allowed?(
          http_verb: action.http_verb,
          action_name: action.name,
          api: api,
          trashed_semantics: trashed_semantics
        )
      end

      %i[get delete].include?(http_verb&.to_sym)
    end

    def resource_handler_verb_and_role(action_name, api:)
      name = action_name.to_s
      return [RESOURCE_VERBS.fetch(name), resource_role(name)] if RESOURCE_ROLES.key?(name)

      action = RecordingStudioApi.capability_action(name, api: api)
      return [nil, nil] unless action

      [action.http_verb, action.required_role]
    end

    def dispatch_include_trashed?(include_trashed:, trashed_semantics: nil, role: nil)
      return false unless include_trashed
      return true if trashed_semantics.nil?

      edit_or_higher?(role)
    end

    def edit_or_higher?(role)
      return false if role.blank?

      RecordingStudio::AccessRoles.satisfies?(role: role, minimum_role: :edit)
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
