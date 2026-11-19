# frozen_string_literal: true

class ApiExtensionAutoloadError < StandardError
end

class ApiExtensionAutoloadController < ActionController::API
  def show
    raise ApiExtensionAutoloadError, "autoloaded controller"
  end
end
