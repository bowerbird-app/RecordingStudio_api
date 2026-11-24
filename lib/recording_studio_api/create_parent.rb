# frozen_string_literal: true

module RecordingStudioApi
  module CreateParent
    CLIENT = :client
    SERVER = :server
    VALUES = [CLIENT, SERVER].freeze
    SERVER_FLAG = "server"

    module_function

    def normalize(value, name:)
      return CLIENT if value.nil?

      symbol = value.to_sym
      return symbol if VALUES.include?(symbol)

      raise ConfigurationError, "#{name} must be :client or :server"
    end

    def server?(value)
      !value.nil? && value.to_sym == SERVER
    end

    def catalog_flag(server)
      SERVER_FLAG if server
    end
  end
end
