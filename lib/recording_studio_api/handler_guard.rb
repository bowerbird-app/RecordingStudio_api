# frozen_string_literal: true

module RecordingStudioApi
  # Scope and authorize a recording before a caller runs the handler.
  class HandlerGuard
    Result = Data.define(:recording, :parent_recording)
    MISSING = "Resource was not found in this API scope"
    SCOPED_RESOURCE_ACTIONS = %i[show update destroy].freeze

    class << self
      def resource!(access_grant:, recordable_type:, action_name:, id:, registration:)
        action = action_name.to_sym
        return empty_result if HandlerScope.resource_opt_out?(registration.owns_scoping?, action) || !SCOPED_RESOURCE_ACTIONS.include?(action)

        role = HandlerScope.resource_role(action)
        include_trashed = include_trashed?(registration, role: role)
        recording = find_recording!(access_grant:, id:, recordable_type:, include_trashed:)
        authorize_recording!(access_grant, recording, role, include_trashed)
        result_for(recording)
      end

      def capability!(access_grant:, api_client:, recordable_type:, action:, id:, registration:, before_authorize: nil)
        source = registration || action
        # An owns_scoping read yields nil and returns. The handler owns scoping.
        # Lookup, before_authorize, and authorize! do not run. The block still runs.
        if source.owns_scoping? && dispatch_read?(action, recording: nil, api_client:, access_grant:)
          yield nil if block_given?
          return empty_result
        end

        include_trashed = include_trashed_for?(
          source:,
          action:,
          access_grant:,
          api_client:,
          recordable_type:,
          id:
        )
        recording = find_recording!(access_grant:, id:, recordable_type:, include_trashed:)
        role = action_role(action, recording:, api_client:, access_grant:)
        disabled_action = disabled_action_error(before_authorize, recording)
        authorize_recording!(access_grant, recording, role, include_trashed)
        raise disabled_action if disabled_action

        yield recording if block_given?
        result_for(recording)
      end

      def endpoint!(access_grant:, endpoint:, id:)
        return empty_result if HandlerScope.endpoint_opt_out?(endpoint) || !endpoint.scopes_recording?

        role = endpoint.authorization_role
        include_trashed = include_trashed?(endpoint, role: role)
        recording = find_recording!(
          access_grant:,
          id:,
          recordable_type: endpoint.recordable_type,
          include_trashed:
        )
        authorize_recording!(access_grant, recording, role, include_trashed)
        result_for(recording)
      end

      private

      def disabled_action_error(check, recording)
        return if check.nil?

        check.call(recording)
        nil
      rescue UnsupportedActionError => e
        e
      end

      def include_trashed_for?(source:, action:, access_grant:, api_client:, recordable_type:, id:)
        return include_trashed?(source, role: nil) if source.trashed_semantics.nil?
        return false unless source.include_trashed

        candidate = find_recording!(access_grant:, id:, recordable_type:, include_trashed: true)
        include_trashed?(
          source,
          role: action_role(action, recording: candidate, api_client:, access_grant:)
        )
      end

      def dispatch_read?(action, recording:, api_client:, access_grant:)
        HandlerScope.dispatch_read?(
          action: action,
          role: action_role(action, recording:, api_client:, access_grant:)
        )
      end

      def action_role(action, recording:, api_client:, access_grant:)
        RecordingStudioApi.configuration.capability_action_role_for(
          action: action,
          recording: recording,
          api_client: api_client,
          access_grant: access_grant
        )
      end

      def include_trashed?(source, role:)
        HandlerScope.dispatch_include_trashed?(
          include_trashed: source.include_trashed,
          trashed_semantics: source.trashed_semantics,
          role: role
        )
      end

      def find_recording!(access_grant:, id:, recordable_type:, include_trashed:)
        raise NotFoundError, MISSING if id.blank?

        ScopedRecording.find!(
          access_grant: access_grant,
          id: id,
          recordable_type: recordable_type,
          include_trashed: include_trashed
        )
      end

      def authorize_recording!(access_grant, recording, role, include_trashed)
        return if role.nil?

        access_grant.authorize!(
          recording: recording,
          role: role,
          include_trashed: include_trashed
        )
      end

      def empty_result
        Result.new(recording: nil, parent_recording: nil)
      end

      def result_for(recording)
        Result.new(recording: recording, parent_recording: nil)
      end
    end
  end
end
