# frozen_string_literal: true

require "test_helper"

class UiMetadataTest < Minitest::Test
  def setup
    @original_configuration = RecordingStudioApi.instance_variable_get(:@configuration)
    RecordingStudioApi.instance_variable_set(:@configuration, RecordingStudioApi::Configuration.new)
  end

  def teardown
    RecordingStudioApi.instance_variable_set(:@configuration, @original_configuration)
  end

  def test_ui_for_returns_registered_widget_id_for_endpoint_and_capability_action
    RecordingStudioApi.register_endpoint(
      "presskits.edit",
      http_verb: :patch,
      path: "presskits/:id",
      handler: ->(_context) { :ok },
      ui: "presskits.editor"
    )
    RecordingStudioApi.register_capability_action(
      :update_presskit,
      capability: :presskits,
      handler: ->(_context) { :ok },
      ui: "presskits.editor"
    )

    assert_equal "presskits.editor", RecordingStudioApi.ui_for("presskits.edit")
    assert_equal "presskits.editor", RecordingStudioApi.ui_for(:update_presskit)
    assert_equal "presskits.editor", RecordingStudioApi.registered_endpoint("presskits.edit").ui
    assert_equal "presskits.editor", RecordingStudioApi.capability_action(:update_presskit).ui
  end

  def test_ui_for_is_nil_when_ui_is_omitted_or_unknown
    RecordingStudioApi.register_endpoint(
      :ping,
      http_verb: :get,
      path: "ping",
      handler: ->(_context) { { ok: true } }
    )
    RecordingStudioApi.register_capability_action(
      :echo,
      capability: :echoable,
      handler: ->(_context) { :ok }
    )

    assert_nil RecordingStudioApi.ui_for(:ping)
    assert_nil RecordingStudioApi.ui_for(:echo)
    assert_nil RecordingStudioApi.ui_for("missing.action")
    assert_nil RecordingStudioApi.registered_endpoint(:ping).ui
    assert_nil RecordingStudioApi.capability_action(:echo).ui
  end

  def test_ui_metadata_is_scoped_by_named_api
    RecordingStudioApi.register_capability_action(
      :update_presskit,
      capability: :presskits,
      handler: ->(_context) { :ok },
      ui: "presskits.editor"
    )
    RecordingStudioApi.register_capability_action(
      :update_presskit,
      capability: :presskits,
      handler: ->(_context) { :ok },
      ui: "operations.presskits.editor",
      api: :operations
    )
    RecordingStudioApi.register_endpoint(
      "presskits.edit",
      http_verb: :patch,
      path: "presskits/:id",
      handler: ->(_context) { :ok },
      ui: "presskits.editor"
    )
    RecordingStudioApi.register_endpoint(
      "presskits.edit",
      api: :operations,
      http_verb: :patch,
      path: "presskits/:id",
      handler: ->(_context) { :ok },
      ui: "operations.presskits.editor"
    )

    assert_equal "presskits.editor", RecordingStudioApi.ui_for(:update_presskit)
    assert_equal "operations.presskits.editor", RecordingStudioApi.ui_for(:update_presskit, api: :operations)
    assert_equal "presskits.editor", RecordingStudioApi.ui_for("presskits.edit")
    assert_equal "operations.presskits.editor", RecordingStudioApi.ui_for("presskits.edit", api: :operations)
    assert_equal ["update_presskit", "presskits.edit"], RecordingStudioApi.actions_for_ui("presskits.editor").map(&:name)
    assert_equal ["update_presskit", "presskits.edit"], RecordingStudioApi.actions_for_ui("operations.presskits.editor", api: :operations).map(&:name)
    assert_empty RecordingStudioApi.actions_for_ui("presskits.editor", api: :operations)
  end

  def test_ui_metadata_honors_version_profiles
    RecordingStudioApi.register_capability_action(
      :update_presskit,
      capability: :presskits,
      version: "1.0.0",
      handler: ->(_context) { :v1 },
      ui: "presskits.editor.v1"
    )
    RecordingStudioApi.register_capability_action(
      :update_presskit,
      capability: :presskits,
      version: "2.0.0",
      handler: ->(_context) { :v2 },
      ui: "presskits.editor.v2"
    )
    RecordingStudioApi.configuration.version("v1") { |api| api.use :presskits, "~> 1.0" }
    RecordingStudioApi.configuration.version("v2") { |api| api.use :presskits }

    assert_equal "presskits.editor.v1", RecordingStudioApi.ui_for(:update_presskit, version: "v1")
    assert_equal "presskits.editor.v2", RecordingStudioApi.ui_for(:update_presskit, version: "v2")
    assert_equal "presskits.editor.v2", RecordingStudioApi.ui_for(:update_presskit)
    assert_equal ["update_presskit"], RecordingStudioApi.actions_for_ui("presskits.editor.v1", version: "v1").map(&:name)
    assert_empty RecordingStudioApi.actions_for_ui("presskits.editor.v2", version: "v1")
    assert_equal ["update_presskit"], RecordingStudioApi.actions_for_ui("presskits.editor.v2", version: "v2").map(&:name)
  end

  def test_actions_for_ui_finds_matching_registrations
    RecordingStudioApi.register_capability_action(
      :update_presskit,
      capability: :presskits,
      handler: ->(_context) { :ok },
      ui: "presskits.editor"
    )
    RecordingStudioApi.register_endpoint(
      "presskits.edit",
      http_verb: :patch,
      path: "presskits/:id",
      handler: ->(_context) { :ok },
      ui: "presskits.editor"
    )
    RecordingStudioApi.register_endpoint(
      :ping,
      http_verb: :get,
      path: "ping",
      handler: ->(_context) { { ok: true } },
      ui: "status.ping"
    )

    matches = RecordingStudioApi.actions_for_ui("presskits.editor")

    assert_equal ["update_presskit", "presskits.edit"], matches.map(&:name)
    assert_equal ["presskits.editor"], matches.map(&:ui).uniq
    assert_empty RecordingStudioApi.actions_for_ui(nil)
    assert_empty RecordingStudioApi.actions_for_ui("missing.widget")
  end

  def test_existing_registrations_without_ui_stay_unchanged
    RecordingStudioApi.register_capability_action(
      :echo,
      capability: :echoable,
      version: "1.2.3",
      handler: ->(_context) { :ok }
    )
    RecordingStudioApi.register_endpoint(
      :ping,
      http_verb: :get,
      path: "ping",
      handler: ->(_context) { { ok: true } }
    )

    action = RecordingStudioApi.capability_action(:echo)
    endpoint = RecordingStudioApi.registered_endpoint(:ping)

    assert_equal "echo", action.name
    assert_equal :echoable, action.capability
    assert_equal "1.2.3", action.version.to_s
    assert_equal :post, action.http_verb
    assert_nil action.ui
    assert_equal "ping", endpoint.name
    assert_equal :get, endpoint.http_verb
    assert_equal "ping", endpoint.path
    assert_nil endpoint.ui
    assert_nil action.as_json[:ui]
    assert_nil endpoint.as_json[:ui]
    assert_empty RecordingStudioApi.actions_for_ui("presskits.editor")
  end

  def test_blank_or_non_string_ui_is_rejected
    error = assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioApi.register_endpoint(
        :ping,
        http_verb: :get,
        path: "ping",
        handler: ->(_context) { { ok: true } },
        ui: " "
      )
    end
    assert_equal "ui must be a string widget id for ping", error.message

    error = assert_raises(RecordingStudioApi::ConfigurationError) do
      RecordingStudioApi.register_capability_action(
        :echo,
        capability: :echoable,
        handler: ->(_context) { :ok },
        ui: { id: "presskits.editor" }
      )
    end
    assert_equal "ui must be a string widget id for echo", error.message
  end
end
