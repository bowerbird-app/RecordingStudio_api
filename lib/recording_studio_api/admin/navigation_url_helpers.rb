# frozen_string_literal: true

module RecordingStudioApi
  module Admin
    module NavigationUrlHelpers
      module_function

      def admin_screen_url(context, key, params = {})
        query = params.merge(anchor_url: context.params[:anchor_url] || context.params["anchor_url"]).compact
        path = context.admin_screen_path(key)

        query.present? ? "#{path}?#{query.to_query}" : path
      end
    end
  end
end