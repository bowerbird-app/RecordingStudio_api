# frozen_string_literal: true

require "test_helper"

class RecordingStudioApiTest < Minitest::Test
  def test_version_exists
    assert_not_nil ::RecordingStudioApi::VERSION
  end

  def test_engine_exists
    assert_kind_of Class, ::RecordingStudioApi::Engine
  end

  def test_dummy_app_uses_flatpack_sidebar_layout
    layout_path = File.expand_path("dummy/app/views/layouts/flat_pack_sidebar.html.erb", __dir__)
    assert File.exist?(layout_path)

    application_controller_path = File.expand_path("dummy/app/controllers/application_controller.rb", __dir__)
    controller_source = File.read(application_controller_path)
    assert_includes controller_source, "flat_pack_sidebar"
    assert_not_includes controller_source, "flat_pack_admin_sidebar"
  end

  def test_dummy_layouts_default_to_flatpack_rounded_theme
    application_layout = File.read(File.expand_path("dummy/app/views/layouts/application.html.erb", __dir__))
    sidebar_layout = File.read(File.expand_path("dummy/app/views/layouts/flat_pack_sidebar.html.erb", __dir__))

    assert_includes application_layout, '<html data-theme="rounded">'
    assert_includes sidebar_layout, '<html data-theme="rounded" class="h-full overflow-hidden overscroll-none">'
  end

  def test_dummy_tailwind_keeps_flatpack_theme_selection_in_flatpack
    tailwind_source = File.read(File.expand_path("dummy/app/assets/tailwind/application.css", __dir__))

    assert_includes tailwind_source, "../../../vendor/bundle/**/flatpack/app/components/**/*.{rb,erb}"
    assert_includes tailwind_source, "flatpack-*/app/components/**/*.{rb,erb}"
    assert_includes tailwind_source, "../../../vendor/bundle/**/recording_studio/app/views/**/*.erb"
    assert_includes tailwind_source, "recordingstudio-*/app/views/**/*.erb"
    assert_not_includes tailwind_source, "@theme"
    assert_not_includes tailwind_source, ":root {"
    assert_not_includes tailwind_source, "--color-fp-primary"
  end

  def test_recording_studio_capabilities_are_off_by_default
    initializer_path = File.expand_path("dummy/config/initializers/recording_studio.rb", __dir__)
    initializer_source = File.read(initializer_path)

    assert_includes initializer_source, "Built-in capabilities remain disabled"
    assert_not_includes initializer_source, "config.features."
  end

  def test_readme_marks_preserved_template_docs_as_repo_only
    readme_source = File.read(File.expand_path("../README.md", __dir__))

    assert_includes readme_source, "preserved in this repository under `docs/gem_template/`"
    assert_includes readme_source, "not packaged gem docs"
  end

  def test_dummy_readme_explains_dummy_app_purpose
    readme_path = File.expand_path("dummy/README.md", __dir__)
    readme_source = File.read(readme_path)

    assert_includes readme_source, "This Rails app exists to validate the RecordingStudio API integration surface"
    assert_includes readme_source, "/recording_studio_root_switchable/v1/root_switch?scope=all_roots"
    assert_includes readme_source, "/recording_studio"
    assert_includes readme_source, "architecture handoff"
  end

  def test_dummy_home_page_uses_recording_studio_api_title
    standard_root_view_path = File.expand_path("dummy/app/views/home/standard_root.html.erb", __dir__)
    workspace_view_path = File.expand_path("dummy/app/views/home/workspace.html.erb", __dir__)
    folder_view_path = File.expand_path("dummy/app/views/home/folder.html.erb", __dir__)
    admin_root_view_path = File.expand_path("dummy/app/views/recording_studio_admin/home/index.html.erb", __dir__)
    standard_root_view_source = File.read(standard_root_view_path)
    workspace_view_source = File.read(workspace_view_path)
    folder_view_source = File.read(folder_view_path)
    admin_root_view_source = File.read(admin_root_view_path)

    assert_includes standard_root_view_source, 'title: "Recording Studio API demo"'
    assert_includes standard_root_view_source, "Demo to add and remove API access"
    assert_includes standard_root_view_source, 'text: "API"'
    assert_includes standard_root_view_source, "@api_admin_path"
    assert_includes workspace_view_source, 'title: "Workspace"'
    assert_includes folder_view_source, 'title: "Folder"'
    assert_includes admin_root_view_source, 'title: "Admin"'
    assert_includes admin_root_view_source, 'text: "Open Admin API"'
  end

  def test_dummy_docs_pages_use_flatpack_documentation_components
    docs_view_paths = Dir[File.expand_path("dummy/app/views/docs/*.html.erb", __dir__)].reject do |view_path|
      File.basename(view_path).start_with?("_")
    end
    assert_not_empty docs_view_paths

    docs_view_paths.each do |view_path|
      view_source = File.read(view_path)

      if view_source.include?("No methods provided by gem outside of setup")
        assert_includes view_source, "No methods provided by gem outside of setup"
      elsif view_source.include?("scalar-api-reference")
        assert_includes view_source, "scalar-api-reference"
      else
        assert_includes view_source, "FlatPack::PageTitle::Component"
      end
    end

    methods_view = File.read(File.expand_path("dummy/app/views/docs/methods.html.erb", __dir__))
    if methods_view.include?("No methods provided by gem outside of setup")
      assert_includes methods_view, "No methods provided by gem outside of setup"
    else
      assert_includes methods_view, "FlatPack::SectionTitle::Component"
      assert_includes methods_view, "FlatPack::CodeBlock::Component"
    end

    config_view = File.read(File.expand_path("dummy/app/views/docs/config.html.erb", __dir__))
    assert_includes config_view, "FlatPack::CodeBlock::Component"
    assert_includes config_view, "RecordingStudioApi.configure do |config|"

    gem_views_view = File.read(File.expand_path("dummy/app/views/docs/gem_views.html.erb", __dir__))
    assert_includes gem_views_view, "FlatPack::Table::Component"
    assert_includes gem_views_view, "table.column(title: \"Template\""
    assert_includes gem_views_view, "No gem views were found."

    recordable_types_view = File.read(File.expand_path("dummy/app/views/docs/recordable_types.html.erb", __dir__))
    assert_includes recordable_types_view, "FlatPack::Table::Component"

    api_hierarchy_view = File.read(File.expand_path("dummy/app/views/docs/api_hierarchy.html.erb", __dir__))
    assert_includes api_hierarchy_view, 'title: "API hierarchy"'
    assert_includes api_hierarchy_view, "FlatPack::Tree::Component"
    assert_includes api_hierarchy_view, "render_recording_tree_nodes"

    recordings_tree_view = File.read(File.expand_path("dummy/app/views/docs/recordings_tree.html.erb", __dir__))
    assert_includes recordings_tree_view, "FlatPack::Tree::Component"
    assert_not_includes recordings_tree_view, "Current structure"
    assert_not_includes recordings_tree_view, "This tree is generated from RecordingStudio::Recording records"
  end

  def test_dummy_recordings_tree_view_omits_structure_section_copy
    recordings_tree_view = File.read(File.expand_path("dummy/app/views/docs/recordings_tree.html.erb", __dir__))

    assert_includes recordings_tree_view, 'title: "Recordings tree"'
    assert_includes recordings_tree_view, "FlatPack::Tree::Component"
    assert_includes recordings_tree_view, "render_recording_tree_nodes"
    assert_not_includes recordings_tree_view, "Current structure"
    assert_not_includes recordings_tree_view, "This tree is generated from RecordingStudio::Recording records"
  end

  def test_dummy_sidebar_includes_recordings_tree_navigation
    sidebar_path = File.expand_path("dummy/app/views/layouts/flat_pack/_sidebar.html.erb", __dir__)
    sidebar_source = File.read(sidebar_path)

    assert_includes sidebar_source, 'title: "RecordingStudio API"'
    assert_includes sidebar_source, 'subtitle: "Host app guide"'
    assert_includes sidebar_source, 'label: "Admin API"'
    assert_includes sidebar_source, 'RecordingStudioApi.admin_dashboard_path(controller: self)'
    assert_includes sidebar_source, 'label: "Recordable types"'
    assert_includes sidebar_source, "main_app.docs_recordable_types_path"
    assert_includes sidebar_source, 'label: "API hierarchy"'
    assert_includes sidebar_source, "main_app.docs_api_hierarchy_path"
    assert_includes sidebar_source, 'label: "Recordings tree"'
    assert_includes sidebar_source, "main_app.docs_recordings_tree_path"
    assert_includes sidebar_source, 'label: "Versions"'
    assert_includes sidebar_source, "main_app.docs_versions_path"
    assert_not_includes sidebar_source, 'title: "Addon Template"'
  end

  def test_dummy_sidebar_uses_supported_icons_for_install_and_methods
    sidebar_path = File.expand_path("dummy/app/views/layouts/flat_pack/_sidebar.html.erb", __dir__)
    sidebar_source = File.read(sidebar_path)

    assert_includes sidebar_source, 'label: "Install"'
    assert_includes sidebar_source, "icon: :arrow_down_tray"
    assert_includes sidebar_source, 'label: "Methods"'
    assert_includes sidebar_source, "icon: :code_bracket"
    assert_not_includes sidebar_source, "icon: :download"
    assert_not_includes sidebar_source, "icon: :code\n"
  end

  def test_dummy_top_nav_uses_root_switchable_dropdown_without_center_label
    top_nav_path = File.expand_path("dummy/app/views/layouts/flat_pack/_top_nav.html.erb", __dir__)
    top_nav_source = File.read(top_nav_path)

    assert_not_includes top_nav_source, "nav.center"
    assert_includes top_nav_source, "recording_studio_root_switch_dropdown("
    assert_includes top_nav_source, 'return_to: request.fullpath'
    assert_not_includes top_nav_source, "\#{current_root_name} - Change"
    assert_not_includes top_nav_source, 'recording_studio_root_switchable.root_switch_path('
  end

  def test_dummy_application_controller_exposes_root_switchable_support
    controller_path = File.expand_path("dummy/app/controllers/application_controller.rb", __dir__)
    controller_source = File.read(controller_path)

    assert_includes controller_source, "include RecordingStudio::RootSwitchable::ControllerSupport"
    assert_includes controller_source, 'current_root.recordable_type == "AdminRoot"'
  end

  def test_dummy_routes_mount_admin_accessible_and_root_switchable_engines
    routes_path = File.expand_path("dummy/config/routes.rb", __dir__)
    routes_source = File.read(routes_path)

    assert_includes routes_source, 'mount RecordingStudioAccessible::Engine, at: "/recording_studio_accessible"'
    assert_includes routes_source, 'mount RecordingStudioRootSwitchable::Engine, at: "/recording_studio_root_switchable"'
    assert_includes routes_source, 'mount RecordingStudioAccessible::Engine, at: "/admin/access", as: :recording_studio_admin_access'
    assert_includes routes_source, 'recording_studio_admin_for :api, at: "/api", root_section: :api'
    assert_not_includes routes_source, 'root_section: :api_admin'
    assert_includes routes_source, 'get "/admin/api", to: "recording_studio_api/admin_dashboards#show", as: :admin_api'
    assert_includes routes_source, 'get "/admin/api/requests", to: "recording_studio_api/admin_requests#index", as: :admin_api_requests'
    assert_includes routes_source, 'get "/admin/api/errors", to: "recording_studio_api/admin_errors#index", as: :admin_api_errors'
    assert_not_includes routes_source, 'mount RecordingStudioAdmin::Engine, at: "/admin"'
  end

  def test_dummy_root_switchable_initializer_uses_all_roots_scope_for_admin_flow
    initializer_path = File.expand_path("dummy/config/initializers/recording_studio_root_switchable.rb", __dir__)
    initializer_source = File.read(initializer_path)

    assert_includes initializer_source, 'recording_studio/default_layout'
    assert_includes initializer_source, "config.scope :all_roots"
    assert_includes initializer_source, 'recording.recordable_type == "AdminRoot"'
    assert_includes initializer_source, "nested_return_to = Rack::Utils.parse_nested_query"
    assert_includes initializer_source, 'resolved_return_to_path.start_with?("/admin")'
  end

  def test_dummy_admin_initializer_uses_controller_current_root_recording
    initializer_path = File.expand_path("dummy/config/initializers/recording_studio_admin.rb", __dir__)
    initializer_source = File.read(initializer_path)

    assert_includes initializer_source, "config.access_recording_resolver"
    assert_includes initializer_source, 'AdminRoot.find_by(name: "Admin")'
    assert_includes initializer_source, "config.site_admin_recording_resolver = config.access_recording_resolver"
  end

  def test_dummy_api_initializer_configures_admin_dashboard_path_resolver
    initializer_path = File.expand_path("dummy/config/initializers/recording_studio_api.rb", __dir__)
    initializer_source = File.read(initializer_path)

    assert_includes initializer_source, 'config.admin_layout_name = "flat_pack_sidebar"'
    assert_includes initializer_source, "config.admin_dashboard_path_resolver"
    assert_includes initializer_source, "config.admin_requests_path_resolver"
    assert_includes initializer_source, "config.admin_errors_path_resolver"
    assert_includes initializer_source, "config.admin_logs_path_resolver"
    assert_includes initializer_source, "controller.main_app.admin_api_path"
    assert_includes initializer_source, "controller.main_app.admin_api_requests_path"
    assert_includes initializer_source, "controller.main_app.admin_api_errors_path"
    assert_includes initializer_source, "controller.main_app.admin_api_logs_path"
  end

  def test_engine_ships_admin_api_dashboard_view_and_model
    dashboard_view = File.expand_path("../app/views/recording_studio_api/admin_dashboards/show.html.erb", __dir__)
    admin_requests_view = File.expand_path("../app/views/recording_studio_api/admin_requests/index.html.erb", __dir__)
    admin_errors_view = File.expand_path("../app/views/recording_studio_api/admin_errors/index.html.erb", __dir__)
    model_path = File.expand_path("../app/models/recording_studio_api/admin_api.rb", __dir__)

    assert File.exist?(dashboard_view)
    assert File.exist?(admin_requests_view)
    assert File.exist?(admin_errors_view)
    assert File.exist?(model_path)
  end

  def test_engine_ships_flatpack_access_request_views
    engine_views = Dir[File.expand_path("../app/views/recording_studio_api/**/*.erb", __dir__)]

    assert_includes engine_views, File.expand_path("../app/views/recording_studio_api/access_requests/index.html.erb", __dir__)
    assert_includes engine_views, File.expand_path("../app/views/recording_studio_api/access_requests/new.html.erb", __dir__)
    assert_includes engine_views, File.expand_path("../app/views/recording_studio_api/access_requests/create.html.erb", __dir__)
    assert_includes engine_views, File.expand_path("../app/views/recording_studio_api/access_requests/show.html.erb", __dir__)
  end

  def test_dummy_layouts_do_not_render_legacy_icon_sprite
    application_layout = File.read(File.expand_path("dummy/app/views/layouts/application.html.erb", __dir__))
    sidebar_layout = File.read(File.expand_path("dummy/app/views/layouts/flat_pack_sidebar.html.erb", __dir__))

    assert_not_includes application_layout, 'render "layouts/icon_sprite"'
    assert_not_includes sidebar_layout, 'render "layouts/icon_sprite"'
    assert_not File.exist?(File.expand_path("dummy/app/views/layouts/_icon_sprite.html.erb", __dir__))
  end

  def test_dummy_views_no_longer_include_legacy_makeup_artist_namespace
    assert_not Dir.exist?(File.expand_path("dummy/app/views/makeup_artist", __dir__))
  end
end
