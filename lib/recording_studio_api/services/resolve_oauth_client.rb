# frozen_string_literal: true

require "ipaddr"
require "json"
require "net/http"
require "resolv"
require "uri"

module RecordingStudioApi
  module Services
    class ResolveOauthClient < BaseService
      CIMD_TIMEOUT_SECONDS = 3
      PRIVATE_NETWORKS = [
        IPAddr.new("0.0.0.0/8"),
        IPAddr.new("10.0.0.0/8"),
        IPAddr.new("127.0.0.0/8"),
        IPAddr.new("169.254.0.0/16"),
        IPAddr.new("172.16.0.0/12"),
        IPAddr.new("192.168.0.0/16"),
        IPAddr.new("::1/128"),
        IPAddr.new("fc00::/7"),
        IPAddr.new("fe80::/10")
      ].freeze

      def initialize(client_id:, api: :public)
        @client_id = client_id.to_s
        @api_key = RecordingStudioApi.configuration.fetch_api(api).name
      end

      private

      attr_reader :client_id, :api_key

      def perform
        return failure("client_id is required") if client_id.blank?

        client = OauthClient.find_by(client_id: client_id)
        client ||= resolve_client_id_metadata_document
        return failure("unknown client") if client.nil?
        return failure("client is revoked") if client.revoked?
        return failure("client is not registered for this API") unless client.api_key == api_key

        success(client)
      end

      def resolve_client_id_metadata_document
        return unless RecordingStudioApi.configuration.client_id_metadata_documents_enabled
        return unless https_client_id_url?

        metadata = fetch_metadata_document
        return if metadata.blank?
        return unless metadata["client_id"].to_s == client_id
        return if Array(metadata["redirect_uris"]).empty?

        OauthClient.create!(
          name: metadata["client_name"].presence || client_id,
          client_id: client_id,
          confidential: false,
          redirect_uris: Array(metadata["redirect_uris"]).map(&:to_s),
          api_key: api_key
        )
      rescue ActiveRecord::RecordNotUnique
        OauthClient.find_by(client_id: client_id)
      rescue StandardError
        nil
      end

      def https_client_id_url?
        uri = URI.parse(client_id)
        uri.is_a?(URI::HTTPS) && uri.host.present? && uri.fragment.nil? && !private_host?(uri)
      rescue URI::InvalidURIError
        false
      end

      def fetch_metadata_document
        uri = URI.parse(client_id)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = CIMD_TIMEOUT_SECONDS
        http.read_timeout = CIMD_TIMEOUT_SECONDS
        request = Net::HTTP::Get.new(uri)
        request["Accept"] = "application/json"
        response = http.request(request)
        return unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body)
      rescue StandardError
        nil
      end

      def private_host?(uri)
        addr = IPAddr.new(Resolv.getaddress(uri.host))
        PRIVATE_NETWORKS.any? { |network| network.include?(addr) }
      rescue Resolv::ResolvError, IPAddr::Error, SocketError
        true
      end
    end
  end
end
