# frozen_string_literal: true

module RecordingStudioApi
  module AccessRequests
    # Admin roots are not public access points. The new-key form keeps that
    # root for navigation and offers manageable roots that are access points,
    # instead of nesting a workspace under the admin root. A workspace stays
    # on the access points already in its tree.
    module AccessPointRootChoice
      extend ActiveSupport::Concern

      private

      def show_access_point_root_choice?
        root_recording = selected_root_recording
        root_recording.present? &&
          admin_root_recording?(root_recording) &&
          available_access_point_recordings(root_recording).empty?
      end

      def access_point_candidates_for_request
        in_tree = available_access_point_recordings(selected_root_recording)
        return in_tree if in_tree.any?
        return manageable_access_point_roots if show_access_point_root_choice?

        []
      end

      def manageable_access_point_roots
        access_point_types = RecordingStudioApi.api_access_point_recordable_types(api: selected_api.name)
        manageable_root_recordings.select { |recording| access_point_types.include?(recording.recordable_type) }
      end

      def access_point_root_choice_label
        types = manageable_access_point_roots.map(&:recordable_type).uniq
        return "Workspace" if types.empty?
        return recordable_type_label(types.first) if types.one?

        types.map { |type_name| recordable_type_label(type_name) }.to_sentence
      end

      def access_point_root_choice_help
        "Pick where this key can work."
      end

      def access_point_root_choice_empty_message
        "You need a #{access_point_root_choice_label.downcase} you can manage before you can create this key."
      end

      def recordable_type_label(type_name)
        declaration = RecordingStudio.recordable_declaration_for(type_name)
        label = declaration.label if declaration.respond_to?(:label)
        return label if label.present?

        type_name.to_s.demodulize.underscore.humanize
      end

      def admin_root_recording?(recording)
        return false if recording.nil?

        names = RecordingStudioApi.configuration.admin_root_recordable_type_names
        names.map(&:to_s).include?(recording.recordable_type.to_s)
      end
    end
  end
end
