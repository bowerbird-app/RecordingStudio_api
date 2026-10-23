# frozen_string_literal: true

module RecordingStudioApi
  # The record that authorized an OAuth token, stored beside the API client actor.
  #
  # Recording Studio Oauth keeps that record on OauthAuthorization#manager_actor.
  # The access token authenticator returns the access token as the credential, and
  # that token belongs to the authorization. API credentials have no manager, so
  # those writes do not add one. Client-sent authorized_by keys are removed
  # on every write, including client_credentials and API-key writes.
  module AuthorizedBy
    OMITTED = Object.new
    CLAIMED_KEYS = %w[authorized_by_type authorized_by_id].freeze

    # Reads authorized_by from the access grant. The grant is the only lookup:
    # omitted keywords resolve there, and an explicit value is used as given.
    module Context
      def authorized_by
        grant = access_grant
        grant.authorized_by if grant.respond_to?(:authorized_by)
      end

      def with_authorized_by(metadata = {})
        AuthorizedBy.merge(metadata, authorized_by)
      end
    end

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
      base = without_client_claims(metadata)
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

    def without_client_claims(metadata)
      hash_pairs(metadata).each_with_object({}) do |(key, value), cleaned|
        next if claimed_key?(key)

        cleaned[key] = value
      end
    end
    private_class_method :without_client_claims

    def hash_pairs(metadata)
      return [] if metadata.blank?

      source = if metadata.respond_to?(:to_unsafe_h)
                 metadata.to_unsafe_h
               elsif metadata.respond_to?(:to_h)
                 metadata.to_h
               else
                 {}
               end
      source.to_a
    end
    private_class_method :hash_pairs

    def claimed_key?(key)
      CLAIMED_KEYS.include?(key.to_s)
    end
    private_class_method :claimed_key?
  end
end
