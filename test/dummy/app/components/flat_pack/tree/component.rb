# frozen_string_literal: true

module FlatPack
  module Tree
    class Component < FlatPack::BaseComponent
      Node = Struct.new(
        :label,
        :href,
        :icon,
        :expanded,
        :active,
        :meta,
        :children,
        :system_arguments,
        keyword_init: true
      )

      class Builder
        attr_reader :nodes

        def initialize(component)
          @component = component
          @nodes = []
        end

        def node(label:, href: nil, icon: nil, expanded: false, active: false, meta: nil, **system_arguments, &block)
          @nodes << @component.send(
            :build_node,
            label: label,
            href: href,
            icon: icon,
            expanded: expanded,
            active: active,
            meta: meta,
            system_arguments: system_arguments,
            &block
          )
        end
      end

      def initialize(compact: false, guides: true, **system_arguments)
        super(**system_arguments)
        @compact = compact
        @guides = guides
        @nodes = []
      end

      def node(label:, href: nil, icon: nil, expanded: false, active: false, meta: nil, **system_arguments, &block)
        @nodes << build_node(
          label: label,
          href: href,
          icon: icon,
          expanded: expanded,
          active: active,
          meta: meta,
          system_arguments: system_arguments,
          &block
        )
      end

      def call
        content

        content_tag(:div, **tree_attributes) do
          safe_join(@nodes.map.with_index { |tree_node, index| render_node(tree_node, level: 1, index: index) })
        end
      end

      private

      def build_node(label:, href:, icon:, expanded:, active:, meta:, system_arguments:, &block)
        child_builder = Builder.new(self)
        block&.call(child_builder)

        sanitized_href = sanitize_url(href)
        validate_href!(href, sanitized_href)

        Node.new(
          label: label,
          href: sanitized_href,
          icon: icon || default_icon(child_builder.nodes.any?),
          expanded: expanded,
          active: active,
          meta: meta,
          children: child_builder.nodes,
          system_arguments: sanitize_args(system_arguments)
        )
      end

      def render_node(tree_node, level:, index:)
        return render_leaf_node(tree_node, level: level, index: index) if tree_node.children.empty?

        content_tag(:details, open: tree_node.expanded, class: "group space-y-0.5") do
          safe_join([
            content_tag(:summary, render_branch_row(tree_node, level: level), **summary_attributes(tree_node, level: level)),
            content_tag(
              :div,
              safe_join(tree_node.children.map.with_index { |child, child_index| render_node(child, level: level + 1, index: child_index) }),
              **children_attributes
            )
          ])
        end
      end

      def render_branch_row(tree_node, level:)
        safe_join([
          render_active_indicator(tree_node),
          content_tag(:span, render_chevron_icon, class: "flex h-4 w-4 items-center justify-center text-[var(--surface-muted-content-color)] transition-transform group-open:rotate-90"),
          render_node_icon(tree_node),
          content_tag(:span, tree_node.label, class: branch_label_classes(level)),
          render_meta(tree_node)
        ].compact)
      end

      def render_leaf_node(tree_node, level:, index:)
        row = render_leaf_row(tree_node, level: level)

        content_tag(:div, **leaf_wrapper_attributes(tree_node, level: level, index: index)) do
          if tree_node.href.present?
            link_to(tree_node.href, class: "flex min-w-0 flex-1 items-center gap-1.5", aria: {current: ("page" if tree_node.active)}) { row }
          else
            row
          end
        end
      end

      def render_leaf_row(tree_node, level:)
        safe_join([
          render_active_indicator(tree_node),
          content_tag(:span, nil, class: "block h-4 w-4 flex-none"),
          render_node_icon(tree_node),
          content_tag(:span, tree_node.label, class: leaf_label_classes(level)),
          render_meta(tree_node)
        ].compact)
      end

      def render_active_indicator(tree_node)
        return unless tree_node.active

        content_tag(:span, nil, class: "absolute inset-y-0 left-0 w-0.5 rounded-full bg-[var(--color-primary)]")
      end

      def render_chevron_icon
        render FlatPack::Shared::IconComponent.new(name: "chevron-right", size: :sm)
      end

      def render_node_icon(tree_node)
        return unless tree_node.icon.present?

        content_tag(:span, class: "flex h-4 w-4 flex-none items-center justify-center text-[var(--surface-muted-content-color)]") do
          render FlatPack::Shared::IconComponent.new(name: tree_node.icon, size: :sm)
        end
      end

      def render_meta(tree_node)
        return if tree_node.meta.blank?

        content_tag(:span, tree_node.meta, class: "ml-auto truncate text-xs text-[var(--surface-muted-content-color)]")
      end

      def tree_attributes
        merge_attributes(
          class: tree_classes,
          role: "tree"
        )
      end

      def tree_classes
        classes(
          "w-full text-sm text-[var(--surface-content-color)] select-none",
          ("space-y-0.5" unless @compact)
        )
      end

      def summary_attributes(tree_node, level:)
        merge_node_attributes(
          tree_node,
          class: row_classes(tree_node),
          role: "treeitem",
          tabindex: 0,
          aria: {
            expanded: tree_node.expanded,
            selected: tree_node.active,
            level: level
          }
        )
      end

      def children_attributes
        {
          class: children_classes,
          role: "group"
        }
      end

      def children_classes
        classes(
          "ml-3.5 mt-0.5 pl-2 space-y-0.5",
          ("border-l border-[var(--surface-border-color)]" if @guides)
        )
      end

      def leaf_wrapper_attributes(tree_node, level:, index:)
        merge_node_attributes(
          tree_node,
          class: row_classes(tree_node),
          role: "treeitem",
          tabindex: 0,
          aria: {
            selected: tree_node.active,
            level: level,
            posinset: index + 1
          }
        )
      end

      def row_classes(tree_node)
        classes(
          "group relative flex items-center gap-1.5 overflow-hidden rounded-[var(--radius-sm)] px-2 text-left transition-colors outline-none",
          row_padding_classes,
          "hover:bg-[var(--surface-subtle-background-color)] focus-visible:ring-2 focus-visible:ring-[var(--button-focus-ring-color)] focus-visible:ring-inset",
          ("bg-[var(--surface-subtle-background-color)]" if tree_node.active),
          tree_node.system_arguments[:class]
        )
      end

      def row_padding_classes
        @compact ? "py-1" : "py-1.5"
      end

      def branch_label_classes(level)
        classes(
          "min-w-0 truncate",
          ("font-medium" if level <= 2)
        )
      end

      def leaf_label_classes(_level)
        classes("min-w-0 truncate")
      end

      def merge_node_attributes(tree_node, **additional_attrs)
        node_attributes = tree_node.system_arguments.dup
        node_class = node_attributes.delete(:class)
        node_data = node_attributes.delete(:data) || {}
        node_aria = node_attributes.delete(:aria) || {}

        {
          class: TailwindMerge::Merger.new.merge([additional_attrs.delete(:class), node_class].compact.join(" ")),
          data: node_data.merge(additional_attrs.delete(:data) || {}),
          aria: node_aria.merge(additional_attrs.delete(:aria) || {})
        }.merge(node_attributes).merge(additional_attrs).compact
      end

      def default_icon(branch)
        branch ? :folder : "document-text"
      end

      def sanitize_url(url)
        return nil if url.nil?

        FlatPack::AttributeSanitizer.sanitize_url(url)
      end

      def validate_href!(original_url, sanitized_url)
        return unless original_url.present?
        return if sanitized_url.present?

        raise ArgumentError, "Unsafe URL detected. Only http, https, mailto, tel protocols and relative URLs are allowed."
      end
    end
  end
end