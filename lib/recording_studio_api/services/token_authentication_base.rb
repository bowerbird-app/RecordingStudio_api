# frozen_string_literal: true

module RecordingStudioApi
  module Services
    class TokenAuthenticationBase < BaseService
      def initialize(authorization_header:)
        @authorization_header = authorization_header
      end

      private

      attr_reader :authorization_header

      def perform
        token = parse_bearer_token
        return failure(AuthenticationError.new(missing_token_error_message)) if token.blank?
        return failure(AuthenticationError.new(invalid_token_format_error_message)) unless valid_token_format?(token)

        credential, token_record = resolve_authenticated_entities(token)
        return failure(AuthenticationError.new(invalid_token_error_message)) if credential.nil?
        return failure(AuthenticationError.new(inactive_token_error_message)) unless token_record_active?(token_record)
        return failure(AuthenticationError.new(inactive_token_error_message)) unless credential.active_for_authentication?
        return failure(AuthenticationError.new(inactive_token_error_message)) unless access_recording_active?(credential)

        scope_recording = resolve_scope_recording(credential)
        return failure(AuthenticationError.new(invalid_scope_error_message)) if scope_recording.nil?

        root_recording = resolve_root_recording(credential)
        return failure(AuthenticationError.new(invalid_scope_error_message)) if root_recording.nil?

        update_last_used!(credential, token_record)

        success(
          AuthenticatedClient.new(
            api_client: credential.api_client,
            credential: credential,
            access_recording: credential.effective_access_recording,
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
        access_recording = credential.effective_access_recording
        access_recording.present? && access_recording.trashed_at.nil?
      end

      def resolve_scope_recording(credential)
        resolve_root_recording(credential)
      end

      def resolve_root_recording(credential)
        access_recording = RecordingStudio::Recording.unscoped.find_by(id: credential.effective_access_recording_id)
        return if access_recording.nil?

        root_id = access_recording.root_recording_id.presence || access_recording.id
        root_recording = RecordingStudio::Recording.unscoped.find_by(id: root_id)
        return if root_recording.nil? || root_recording.trashed_at.present?

        root_recording
      end

      def token_record_active?(_token_record)
        true
      end

      def update_last_used!(credential, _token_record)
        credential.update_column(:last_used_at, Time.current)
      end

      def service_args
        { authorization_header_present: authorization_header.present? }
      end

      def missing_token_error_message
        raise NotImplementedError, "#{self.class}#missing_token_error_message must be implemented"
      end

      def invalid_token_format_error_message
        raise NotImplementedError, "#{self.class}#invalid_token_format_error_message must be implemented"
      end

      def invalid_token_error_message
        raise NotImplementedError, "#{self.class}#invalid_token_error_message must be implemented"
      end

      def inactive_token_error_message
        raise NotImplementedError, "#{self.class}#inactive_token_error_message must be implemented"
      end

      def invalid_scope_error_message
        raise NotImplementedError, "#{self.class}#invalid_scope_error_message must be implemented"
      end

      def valid_token_format?(_token)
        raise NotImplementedError, "#{self.class}#valid_token_format? must be implemented"
      end

      def resolve_authenticated_entities(_token)
        raise NotImplementedError, "#{self.class}#resolve_authenticated_entities must be implemented"
      end
    end
  end
end