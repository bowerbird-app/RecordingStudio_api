# frozen_string_literal: true

class ApiExtensionProbeError < StandardError
end

class ApiExtensionProbeController < ActionController::API
  def show
    raise ApiExtensionProbeError, "probe failed"
  end
end
