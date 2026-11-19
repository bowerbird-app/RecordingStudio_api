# frozen_string_literal: true

class ApiExtensionLoadedError < StandardError
end

class ApiExtensionLoadedController < ActionController::API
  def show
    raise ApiExtensionLoadedError, "loaded controller"
  end
end
