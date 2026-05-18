# frozen_string_literal: true

module RecordingStudioApi
  module Services
    class AuthenticateBearerToken < BaseService
      def initialize(authorization_header:)
        @authorization_header = authorization_header
      end

      private

      attr_reader :authorization_header

      def perform
        token = parse_bearer_token
        return failure(AuthenticationError.new("Bearer token is required")) if token.blank?

        parsed = Token.parse(token)
        return failure(AuthenticationError.new("Bearer token format is invalid")) if parsed.nil?

        credential = ApiCredential.find_by(token_public_id: parsed.fetch(:public_id))
        return failure(AuthenticationError.new("Bearer token is invalid")) if credential.nil?
        return failure(AuthenticationError.new("Bearer token is inactive")) unless credential.active_for_authentication?
        return failure(AuthenticationError.new("Bearer token is inactive")) unless access_recording_active?(credential)

        provided_digest = Token.digest(parsed.fetch(:token))
        return failure(AuthenticationError.new("Bearer token is invalid")) unless secure_compare(credential.token_digest, provided_digest)

        scope_recording = resolve_scope_recording(credential)
        return failure(AuthenticationError.new("Bearer token scope is invalid")) if scope_recording.nil?

        root_recording = resolve_root_recording(credential)
        return failure(AuthenticationError.new("Bearer token scope is invalid")) if root_recording.nil?

        credential.update_column(:last_used_at, Time.current)

        success(
          AuthenticatedClient.new(
            api_client: credential.api_client,
            credential: credential,
            access_recording: credential.access_recording,
            scope_recording: scope_recording,
            root_recording: root_recording
          )
        )
      end

      def parse_bearer_token
        return if authorization_header.blank?

        scheme, token = authorization_header.to_s.split(" ", 2)
        return unless scheme.to_s.casecmp("Bearer").zero?

        token
      end

      def secure_compare(left, right)
        return false if left.blank? || right.blank?
        return false unless left.bytesize == right.bytesize

        ActiveSupport::SecurityUtils.secure_compare(left, right)
      end

      def access_recording_active?(credential)
        credential.access_recording.present? && credential.access_recording.trashed_at.nil?
      end

      def resolve_scope_recording(credential)
        access_recording = RecordingStudio::Recording.unscoped.find_by(id: credential.access_recording_id)
        return if access_recording.nil? || access_recording.trashed_at.present?

        return resolve_root_recording(credential) if access_recording.parent_recording_id.nil?

        parent_recording = RecordingStudio::Recording.unscoped.find_by(id: access_recording.parent_recording_id)
        return if parent_recording.nil? || parent_recording.trashed_at.present?

        parent_recording
      end

      def resolve_root_recording(credential)
        access_recording = RecordingStudio::Recording.unscoped.find_by(id: credential.access_recording_id)
        return if access_recording.nil?

        root_id = access_recording.root_recording_id.presence || access_recording.id
        root_recording = RecordingStudio::Recording.unscoped.find_by(id: root_id)
        return if root_recording.nil? || root_recording.trashed_at.present?

        root_recording
      end

      def service_args
        { authorization_header_present: authorization_header.present? }
      end
    end
  end
end
