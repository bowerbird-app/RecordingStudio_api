# frozen_string_literal: true

module RecordingStudioApi
  # Reads the authorizing human already resolved on the access grant.
  # When a caller such as Recording Studio MCP builds the grant itself,
  # the grant resolves the human from the OAuth credential once.
  module AuthorizingHuman
    def authorized_by
      grant = access_grant if respond_to?(:access_grant)
      return grant.authorized_by if grant.respond_to?(:authorized_by)

      AuthorizedBy.actor_for(credential: credential)
    end

    def with_authorized_by(metadata = {})
      AuthorizedBy.merge(metadata, authorized_by)
    end
  end
end
