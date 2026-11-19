# frozen_string_literal: true

class ApiExtensionBeforeError < StandardError
end

class ApiExtensionBeforeController < ActionController::API
  def show
    raise ApiExtensionBeforeError, "registered first"
  end
end
