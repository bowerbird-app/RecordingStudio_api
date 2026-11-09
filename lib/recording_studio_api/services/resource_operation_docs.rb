# frozen_string_literal: true

module RecordingStudioApi
  module Services
    class ResourceOperationDocs
      CANONICAL_FIELDS = %w[id type root_id parent_id created_at updated_at].freeze

      def initialize(resource_name:, docs_resource_name:, registration:, root: false)
        @resource_name = resource_name.to_s
        @docs_resource_name = docs_resource_name.to_s
        @registration = registration
        @root = root
      end

      def summary_for(operation)
        case operation.to_sym
        when :index then "List #{plural_label}"
        when :show then "Get #{noun_phrase}"
        when :create then "Create #{noun_phrase}"
        when :update then "Update #{noun_phrase}"
        when :destroy then "Delete #{noun_phrase}"
        else
          "#{operation.to_s.humanize} #{plural_label}"
        end
      end

      def description_for(operation)
        case operation.to_sym
        when :index then index_description
        when :show then show_description
        when :create then create_description
        when :update then update_description
        else
          summary_for(operation)
        end
      end

      private

      def index_description
        join_sentences(
          "Returns #{plural_label} the caller can access.",
          fields_sentence("Each record includes"),
          filter_sentence,
          "Paginate with `limit` and `pagination_token`. Sort with `sort` and `order`.",
          "Set `count=true` to return only `{ total_count }` for the same filters.",
          include_sentence
        )
      end

      def show_description
        join_sentences(
          "Returns #{noun_phrase} the caller can access.",
          fields_sentence("The record includes"),
          include_sentence
        )
      end

      def create_description
        join_sentences(
          "Creates #{noun_phrase}. Requires edit access.",
          write_sentence(create_write_names),
          "Send an `Idempotency-Key` header to reuse the first successful response for 24 hours."
        )
      end

      def update_description
        join_sentences(
          "Updates #{noun_phrase}. Requires edit access.",
          write_sentence(update_write_names)
        )
      end

      def fields_sentence(prefix)
        names = response_field_names
        return if names.empty?

        "#{prefix} #{format_list(names)}."
      end

      def filter_sentence
        names = filterable_attribute_names
        return if names.empty?

        filters = ["q"] + names.map { |attribute| "filter[#{attribute}]" }
        "Available filters: #{format_list(filters)}."
      end

      def include_sentence
        names = include_names
        return if names.empty?

        "Optional `include` values: #{format_list(names)}."
      end

      def write_sentence(names)
        return if names.empty?

        "Write #{format_list(names)}."
      end

      def response_field_names
        names = CANONICAL_FIELDS.dup
        return names unless @registration

        names.concat(Array(@registration.output_keys).map(&:to_s))
        @registration.fields.each do |name, field|
          names << name.to_s if field.include == true
        end
        names.uniq
      end

      def filterable_attribute_names
        return [] unless @registration

        Array(@registration.filterable_attributes).map(&:to_s)
      end

      def include_names
        return [] unless @registration

        names = @registration.fields.each_with_object([]) do |(name, field), output|
          output << name.to_s if field.include == :request
        end
        @registration.relationships.each do |name, relationship|
          names << name.to_s if relationship.include == :request
        end
        names.uniq
      end

      def create_write_names
        names = writable_attribute_names.dup
        names.unshift("parent_id") unless @root
        names.uniq
      end

      def update_write_names
        return [] unless @registration

        immutable = Array(@registration.immutable_fields).map(&:to_s)
        writable_attribute_names - immutable
      end

      def writable_attribute_names
        return [] unless @registration

        Array(@registration.writable_attributes).map(&:to_s)
      end

      def plural_label
        @resource_name.tr("_", " ")
      end

      def singular_label
        @docs_resource_name.downcase
      end

      def noun_phrase
        return singular_label if singular_label == plural_label

        article = singular_label.match?(/\A[aeiou]/i) ? "an" : "a"
        "#{article} #{singular_label}"
      end

      def format_list(names)
        names.map { |name| "`#{name}`" }.to_sentence
      end

      def join_sentences(*sentences)
        sentences.compact.join(" ")
      end
    end
  end
end
