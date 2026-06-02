module ApplicationHelper
  def current_root_name
    recordable = current_root_recordable
    return "No current root" if recordable.blank?

    if recordable.respond_to?(:name) && recordable.name.present?
      recordable.name
    elsif defined?(RecordingStudio::Labels)
      RecordingStudio::Labels.title_for(recordable)
    else
      recordable.to_s
    end
  end

  def current_root_tree_path
    case current_root_recordable
    when Workspace
      workspace_path
    when Folder
      folder_path
    end
  end

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
