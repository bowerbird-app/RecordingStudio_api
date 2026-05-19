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
    assert_includes readme_source, "/recording_studio"
    assert_includes readme_source, "architecture handoff"
  end

  def test_dummy_home_page_uses_recording_studio_api_title
    view_path = File.expand_path("dummy/app/views/home/index.html.erb", __dir__)
    view_source = File.read(view_path)

    assert_includes view_source, 'title: "Recording Studio API demo"'
    assert_includes view_source, "Demo to add and remove API access"
    assert_not_includes view_source, 'title: "RecordingStudio API"'
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
    assert_includes config_view, "FlatPack::List::Component"
    assert_includes config_view, "FlatPack::List::Item"

    gem_views_view = File.read(File.expand_path("dummy/app/views/docs/gem_views.html.erb", __dir__))
    assert_includes gem_views_view, "FlatPack::Table::Component"
    assert_includes gem_views_view, "table.column(title: \"Template\""
    assert_includes gem_views_view, "No gem views were found."

    recordable_types_view = File.read(File.expand_path("dummy/app/views/docs/recordable_types.html.erb", __dir__))
    assert_includes recordable_types_view, "FlatPack::List::Component"

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
    assert_includes sidebar_source, 'label: "Recordable types"'
    assert_includes sidebar_source, "docs_recordable_types_path"
    assert_includes sidebar_source, 'label: "Recordings tree"'
    assert_includes sidebar_source, "docs_recordings_tree_path"
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

  def test_dummy_top_nav_uses_center_slot_to_keep_avatar_right_aligned
    top_nav_path = File.expand_path("dummy/app/views/layouts/flat_pack/_top_nav.html.erb", __dir__)
    top_nav_source = File.read(top_nav_path)

    assert_includes top_nav_source, "nav.center"
    assert_includes top_nav_source, 'aria-hidden="true"'
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
