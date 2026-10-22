# frozen_string_literal: true

module RecordingStudioApi
  # The human who authorized an OAuth token, recorded beside the API client actor.
  #
  # Recording Studio Oauth keeps that person on OauthAuthorization#manager_actor.
  # The access token authenticator returns the access token as the credential, and
  # that token belongs to the authorization. API credentials have no human owner,
  # so API-key writes stay untouched.
  module AuthorizedBy
    OMITTED = Object.new

    module_function

    def actor_for(credential: nil, token_record: nil)
      [credential, token_record].uniq.each do |record|
        actor = manager_actor_for(record)
        return actor if actor.present?
      end

      nil
    end

    def metadata_for(actor)
      return {} if actor.blank?

      type_name = polymorphic_name(actor)
      identifier = actor.id if actor.respond_to?(:id)
      return {} if type_name.blank? || identifier.blank?

      {
        authorized_by_type: type_name,
        authorized_by_id: identifier
      }
    end

    def merge(metadata, actor)
      base = metadata.respond_to?(:to_h) ? metadata.to_h : {}
      extra = metadata_for(actor)
      return base if extra.empty?

      base.merge(extra)
    end

    def manager_actor_for(record)
      return if record.nil? || !record.respond_to?(:oauth_authorization)

      authorization = record.oauth_authorization
      return if authorization.nil? || !authorization.respond_to?(:manager_actor)

      authorization.manager_actor
    end
    private_class_method :manager_actor_for

    def polymorphic_name(actor)
      klass = actor.class
      klass.respond_to?(:polymorphic_name) ? klass.polymorphic_name : klass.name
    end
    private_class_method :polymorphic_name
  end
end
