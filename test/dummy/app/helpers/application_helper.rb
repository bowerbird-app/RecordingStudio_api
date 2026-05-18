module ApplicationHelper
	def render_recording_tree_nodes(tree_builder, nodes)
		Array(nodes).each do |node|
			children = Array(node[:children])
			icon = children.any? ? :folder : "document-text"

			if children.any?
				tree_builder.node(label: node[:label], icon: icon, expanded: true) do |child_builder|
					render_recording_tree_nodes(child_builder, children)
				end
			else
				tree_builder.node(label: node[:label], icon: icon)
			end
		end

		nil
	end
end
