# frozen_string_literal: true

module RecordingStudioApi
  # A token sees the owner's live access, limited to the grant anchor.
  # On a user OAuth token, that owner is `authorized_by`.
  # When the credential still has an `oauth_authorization` and `authorized_by`
  # is missing, actor and owner stay blank so `authorize!` refuses.
  # `client_credentials` and API keys without an `oauth_authorization` still
  # fall back to the access actor and `api_client.owner`.
  # `authorize!` uses the lower of the grant role and
  # `RecordingStudioAccessible.role_for` on the recording being checked.
  class AccessGrant
    def initialize(api_client:, credential:, access_recording:, root_recording: nil, authorized_by: AuthorizedBy::OMITTED)
      @api_client = api_client
      @credential = credential
      @access_recording = access_recording
      @root_recording = root_recording
      @authorized_by_source = authorized_by
    end

    attr_reader :api_client, :credential, :access_recording, :root_recording

    def authorized_by
      return @authorized_by if defined?(@authorized_by)

      @authorized_by = resolve_authorized_by
    end

    def access
      access_recording&.recordable
    end

    def actor
      return authorized_by if oauth_authorization?

      authorized_by.presence || (access.actor if access.respond_to?(:actor))
    end

    def role
      access.role if access.respond_to?(:role)
    end

    def scope_recording
      access_recording&.parent_recording || root_recording
    end

    def owner
      return @owner if defined?(@owner)

      @owner = if oauth_authorization?
                 authorized_by
               else
                 authorized_by.presence || owner_from_client || owner_from_actor
               end
    end

    def accessible_recordings(include_trashed: false, scope: nil)
      visible.relation(include_trashed: include_trashed, scope: scope)
    end

    def accessible_recording_ids(include_trashed: false)
      visible.recording_ids(include_trashed: include_trashed)
    end

    def authorized?(recording:, role:, include_trashed: false)
      return false unless recording.present? && ranked?(role)
      return false unless in_scope?(recording, include_trashed)

      held = effective_role(recording)
      held.present? && RecordingStudio::AccessRoles.satisfies?(role: held, minimum_role: role)
    end

    def authorize!(recording:, role:, include_trashed: false)
      return if authorized?(recording: recording, role: role, include_trashed: include_trashed)

      raise RecordingStudioApi::AuthorizationError, AuthorizationError.for_required_role(role)
    end

    private

    def resolve_authorized_by
      return AuthorizedBy.actor_for(credential: credential) if @authorized_by_source.equal?(AuthorizedBy::OMITTED)

      @authorized_by_source
    end

    def oauth_authorization?
      credential.respond_to?(:oauth_authorization) && credential.oauth_authorization.present?
    end

    def owner_from_client
      client = api_client
      return if client.nil? || !client.respond_to?(:owner)

      client.owner
    end

    def owner_from_actor
      person = actor
      return person.owner if person.is_a?(ApiClient)

      person
    end

    def visible
      @visible ||= VisibleRecordings.new(owner: owner, anchor: scope_recording, grant_role: role)
    end

    def ranked?(required)
      RecordingStudio::AccessRoles.value_for(required).present?
    end

    def in_scope?(recording, include_trashed)
      accessible_recordings(include_trashed: include_trashed).exists?(id: recording.id)
    end

    def effective_role(recording)
      person = owner
      return if person.nil? || role.blank?

      lower_role(role, RecordingStudioAccessible.role_for(actor: person, recording: recording))
    end

    def lower_role(left, right)
      left_rank = RecordingStudio::AccessRoles.value_for(left)
      right_rank = RecordingStudio::AccessRoles.value_for(right)
      return if left_rank.nil? || right_rank.nil?

      left_rank <= right_rank ? left.to_sym : right.to_sym
    end
  end
end
