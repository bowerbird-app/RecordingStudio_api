# frozen_string_literal: true

module RecordingStudioApi
  module Admin
    # Kept recordings of a declared root type whose root_recording_id is their own id.
    # Parentless rows of other types also store that column, so the type list is required.
    module RootRecordings
      module_function

      def for_types(types)
        matching_types = Array(types).map(&:to_s) & RecordingStudio.root_recordable_types.map(&:to_s)
        return RecordingStudio::Recording.none if matching_types.empty?

        table = RecordingStudio::Recording.arel_table
        RecordingStudio::Recording.unscoped
                                  .where(recordable_type: matching_types)
                                  .where(table[:root_recording_id].eq(table[:id]))
                                  .kept
      end
    end
  end
end
