# frozen_string_literal: true

module RecordingStudioApi
  class LogRecord < ActiveRecord::Base
    self.abstract_class = true

    def self.table_available?
      connection_pool.with_connection do |connection|
        connection.data_source_exists?(table_name)
      end
    rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
      false
    end

    if defined?(Rails) && Rails.application&.config&.respond_to?(:database_configuration)
      configurations = ActiveRecord::Base.configurations
      logging_config = configurations.configs_for(env_name: Rails.env, name: "api_logging")
      has_logging_db = logging_config.present?

      connects_to database: { writing: :api_logging, reading: :api_logging } if has_logging_db
    end
  end
end
