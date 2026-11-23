# frozen_string_literal: true

require_relative "support/api_dummy_helpers"

class HandlerGuardTest < ActiveSupport::TestCase
  include ApiDummyHelpers

  setup do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    @user = create_user
  end

  teardown do
    reset_recording_studio_api_configuration!
    reset_recording_studio_capabilities!
    Current.actor = nil if defined?(Current)
  end

  test "flat index and create return a nil recording" do
    grant, page = open_grant(:view)
    foreign = foreign_page
    index = register_handler("Page", :index)
    create = register_handler("Page", :create)

    assert_nil_guard guard_resource(grant, index, :index, foreign.id)
    assert_nil_guard guard_resource(grant, index, :index, nil)
    assert_nil_guard guard_resource(grant, create, :create, page.id)
    assert_nil_guard guard_resource(grant, create, :create, "")
  end

  test "an owns_scoping resource read returns a nil recording" do
    grant, = open_grant(:view)
    foreign = foreign_page
    registration = register_handler("Page", :show, owns_scoping: true)

    assert_nil_guard guard_resource(grant, registration, :show, foreign.id)
    assert_nil_guard guard_resource(grant, registration, :show, nil)
    assert_nil_guard guard_resource(grant, registration, :show, " ")
  end

  test "show allows view and update requires edit" do
    view_grant, page = open_grant(:view)
    edit_grant, edit_page = open_grant(:edit)
    show = register_handler("Page", :show)
    update = register_handler("Page", :update)

    shown = guard_resource(view_grant, show, :show, page.id)
    assert_equal page, shown.recording
    assert_nil shown.parent_recording

    assert_forbidden { guard_resource(view_grant, update, :update, page.id) }
    assert_equal edit_page, guard_resource(edit_grant, update, :update, edit_page.id).recording
  end

  test "show raises not found for a blank id, a foreign id, a wrong type, and a trashed recording" do
    grant, page = open_grant(:edit)
    foreign = foreign_page
    show = register_handler("Page", :show)

    assert_missing { guard_resource(grant, show, :show, nil) }
    assert_missing { guard_resource(grant, show, :show, "") }
    assert_missing { guard_resource(grant, show, :show, " ") }
    assert_missing { guard_resource(grant, show, :show, foreign.id) }

    error = assert_raises(RecordingStudioApi::NotFoundError) do
      guard_resource(grant, show, :show, page.parent_recording.id)
    end
    assert_equal type_mismatch_message("Page", "Folder"), error.message

    page.update_column(:trashed_at, Time.current)
    assert_missing { guard_resource(grant, show, :show, page.id) }
  end

  test "include_trashed show returns a trashed recording to a view grant" do
    grant, page = open_grant(:view)
    page.update_column(:trashed_at, Time.current)
    show = register_handler("Page", :show, include_trashed: true)

    assert_equal page, guard_resource(grant, show, :show, page.id).recording
  end

  test "destroy with include_trashed forbids view and returns the trashed recording for edit" do
    view_grant, view_page = open_grant(:view)
    edit_grant, edit_page = open_grant(:edit)
    view_page.update_column(:trashed_at, Time.current)
    edit_page.update_column(:trashed_at, Time.current)
    destroy = register_handler("Page", :destroy, include_trashed: true)

    assert_forbidden { guard_resource(view_grant, destroy, :destroy, view_page.id) }
    assert_equal edit_page, guard_resource(edit_grant, destroy, :destroy, edit_page.id).recording
  end

  test "destroy without include_trashed raises not found for a trashed recording" do
    grant, page = open_grant(:edit)
    page.update_column(:trashed_at, Time.current)
    destroy = register_handler("Page", :destroy)

    assert_missing { guard_resource(grant, destroy, :destroy, page.id) }
  end

  test "an owns_scoping capability read returns nil until the effective role is edit" do
    edit_grant, page = open_grant(:edit)
    view_grant, view_page = open_grant(:view)
    foreign = foreign_page
    action = register_action(:published, http_verb: :get, required_role: :view, owns_scoping: true)

    assert_nil_guard guard_capability(edit_grant, action, foreign.id)
    assert_nil_guard guard_capability(edit_grant, action, nil)

    RecordingStudioApi.configuration.capability_action_roles = { "published" => :edit }

    assert_missing { guard_capability(edit_grant, action, foreign.id) }
    assert_equal page, guard_capability(edit_grant, action, page.id).recording
    assert_forbidden { guard_capability(view_grant, action, view_page.id) }
  end

  test "a capability action scopes the id and requires edit" do
    view_grant, view_page = open_grant(:view)
    edit_grant, page = open_grant(:edit)
    foreign = foreign_page
    action = register_action(:echo, http_verb: :post, required_role: :edit)

    assert_equal page, guard_capability(edit_grant, action, page.id).recording
    assert_forbidden { guard_capability(view_grant, action, view_page.id) }
    assert_missing { guard_capability(edit_grant, action, nil) }
    assert_missing { guard_capability(edit_grant, action, "") }
    assert_missing { guard_capability(edit_grant, action, foreign.id) }

    error = assert_raises(RecordingStudioApi::NotFoundError) do
      guard_capability(edit_grant, action, page.parent_recording.id)
    end
    assert_equal type_mismatch_message("Page", "Folder"), error.message
  end

  test "required_role view authorizes a view grant on a post" do
    grant, page = open_grant(:view)
    action = register_action(:search, http_verb: :post, required_role: :view)

    assert_equal page, guard_capability(grant, action, page.id).recording
  end

  test "required_role admin forbids an edit grant" do
    edit_grant, edit_page = open_grant(:edit)
    admin_grant, admin_page = open_grant(:admin)
    action = register_action(:purge, required_role: :admin)

    assert_forbidden(:admin) { guard_capability(edit_grant, action, edit_page.id) }
    assert_equal admin_page, guard_capability(admin_grant, action, admin_page.id).recording
  end

  test "a collection action with no required role skips authorize and a blank id is not found" do
    grant, page = open_grant(:view)
    action = register_action(:list_pages, http_verb: :get, scope: :collection)

    assert_nil action.required_role
    assert_equal page, guard_capability(grant, action, page.id).recording
    assert_missing { guard_capability(grant, action, nil) }
    assert_missing { guard_capability(grant, action, "") }
  end

  test "a resource handler registration supplies scope flags for a capability action" do
    grant, page = open_grant(:edit)
    page.update_column(:trashed_at, Time.current)
    action = register_action(:touch, http_verb: :post, required_role: :edit)
    registration = register_handler(
      "Page",
      :touch,
      include_trashed: true,
      trashed_semantics: :restore
    )

    assert_missing { guard_capability(grant, action, page.id, registration: nil) }
    assert_equal page, guard_capability(grant, action, page.id, registration: registration).recording
  end

  test "owns_scoping follows the registration when one is passed" do
    grant, = open_grant(:view)
    foreign = foreign_page
    action = register_action(:published_page, http_verb: :get, required_role: :view, owns_scoping: true)
    registration = register_handler("Page", :published_page)

    assert_nil_guard guard_capability(grant, action, foreign.id, registration: nil)
    assert_missing { guard_capability(grant, action, foreign.id, registration: registration) }
  end

  test "trashed_semantics asks capability_action_role_for with the trashed candidate" do
    grant, page = open_grant(:edit)
    page.update_column(:trashed_at, Time.current)
    action = register_action(
      :trashable_restore,
      http_verb: :post,
      required_role: :edit,
      include_trashed: true,
      trashed_semantics: :restore
    )
    seen = []
    RecordingStudioApi.configuration.capability_action_role_resolver = lambda do |recording:, **|
      seen << recording
      :view
    end

    assert_missing { guard_capability(grant, action, page.id) }
    assert_equal [page.id], seen.map(&:id)

    page.update_column(:trashed_at, nil)
    assert_equal page, guard_capability(grant, action, page.id).recording
    assert_equal [page.id, page.id, page.id], seen.map(&:id)
  end

  test "a later view role does not include trashed recordings" do
    grant, page = open_grant(:edit)
    action = register_action(:trashable_restore, include_trashed: true, trashed_semantics: :restore)
    RecordingStudioApi.configuration.capability_action_roles = { "trashable_restore" => :view }
    page.update_column(:trashed_at, Time.current)

    assert_missing { guard_capability(grant, action, page.id) }

    page.update_column(:trashed_at, nil)
    assert_equal page, guard_capability(grant, action, page.id).recording
  end

  test "the capability block runs after authorize" do
    view_grant, page = open_grant(:view)
    edit_grant, edit_page = open_grant(:edit)
    action = register_action(:echo_block, required_role: :edit)
    seen = []

    assert_forbidden do
      guard_capability(view_grant, action, page.id) do |recording|
        seen << recording.id
      end
    end
    assert_empty seen

    result = guard_capability(edit_grant, action, edit_page.id) do |recording|
      seen << recording.id
    end
    assert_equal [edit_page.id], seen
    assert_equal edit_page, result.recording
  end

  test "before_authorize runs after lookup and a disabled action keeps the 403 or 404" do
    view_grant, page = open_grant(:view)
    edit_grant, edit_page = open_grant(:edit)
    foreign = foreign_page
    action = register_action(:echo_block, required_role: :edit)
    checks = []
    blocked = []
    check = lambda do |recording|
      checks << recording.id
      raise RecordingStudioApi::UnsupportedActionError, "echo_block is not enabled for #{recording.recordable_type}"
    end

    assert_forbidden do
      guard_capability(view_grant, action, page.id, before_authorize: check) { blocked << :ran }
    end
    assert_equal [page.id], checks
    assert_empty blocked

    error = assert_raises(RecordingStudioApi::UnsupportedActionError) do
      guard_capability(edit_grant, action, edit_page.id, before_authorize: check) { blocked << :ran }
    end
    assert_equal "echo_block is not enabled for Page", error.message
    assert_empty blocked

    assert_missing { guard_capability(edit_grant, action, nil, before_authorize: check) }
    assert_missing { guard_capability(edit_grant, action, foreign.id, before_authorize: check) }
    assert_equal [page.id, edit_page.id], checks
  end

  test "an owns_scoping read yields nil and skips before_authorize" do
    grant, = open_grant(:view)
    action = register_action(:published, http_verb: :get, required_role: :view, owns_scoping: true)
    yielded = []
    checks = []

    result = guard_capability(
      grant,
      action,
      nil,
      before_authorize: ->(recording) { checks << recording }
    ) do |recording|
      yielded << recording
    end

    assert_nil_guard result
    assert_equal [nil], yielded
    assert_empty checks
  end

  test "an endpoint with scope_id false or no recording id returns nil" do
    grant, page = open_grant(:view)
    foreign = foreign_page
    person = register_endpoint(:person, http_verb: :get, path: "people/:id", scope_id: false)
    ping = register_endpoint(:ping, http_verb: :get, path: "ping")

    assert_nil_guard guard_endpoint(grant, person, foreign.id)
    assert_nil_guard guard_endpoint(grant, person, nil)
    assert_nil_guard guard_endpoint(grant, ping, page.id)
    assert_nil_guard guard_endpoint(grant, ping, "")
  end

  test "an owns_scoping endpoint read returns nil" do
    grant, = open_grant(:view)
    foreign = foreign_page
    endpoint = register_endpoint(
      :public_page,
      http_verb: :get,
      path: "public-pages/:id",
      recordable_type: "Page",
      owns_scoping: true
    )

    assert_nil_guard guard_endpoint(grant, endpoint, foreign.id)
    assert_nil_guard guard_endpoint(grant, endpoint, nil)
  end

  test "an id scoped endpoint allows view on get and requires edit on patch" do
    view_grant, view_page = open_grant(:view)
    edit_grant, edit_page = open_grant(:edit)
    foreign = foreign_page
    read = register_endpoint(:read_page, http_verb: :get, path: "role-pages/:id", recordable_type: "Page")
    write = register_endpoint(:write_page, http_verb: :patch, path: "role-pages/:id", recordable_type: "Page")

    assert_equal view_page, guard_endpoint(view_grant, read, view_page.id).recording
    assert_forbidden { guard_endpoint(view_grant, write, view_page.id) }
    assert_equal edit_page, guard_endpoint(edit_grant, write, edit_page.id).recording
    assert_missing { guard_endpoint(edit_grant, read, nil) }
    assert_missing { guard_endpoint(edit_grant, read, "") }
    assert_missing { guard_endpoint(edit_grant, read, foreign.id) }

    error = assert_raises(RecordingStudioApi::NotFoundError) do
      guard_endpoint(edit_grant, read, edit_page.parent_recording.id)
    end
    assert_equal type_mismatch_message("Page", "Folder"), error.message
  end

  test "an unscoped endpoint authorizes the grant anchor" do
    view_grant, = open_grant(:view)
    edit_grant, = open_grant(:edit)
    create_note = register_endpoint(:create_note, http_verb: :post, path: "notes")
    revise_note = register_endpoint(:revise_note, http_verb: :patch, path: "notes")
    remove_person = register_endpoint(
      :remove_person,
      http_verb: :delete,
      path: "people/:id",
      scope_id: false,
      required_role: :edit
    )
    mark_read = register_endpoint(
      :mark_read,
      http_verb: :post,
      path: "notes/:id/read",
      scope_id: false,
      required_role: :view
    )

    assert_forbidden { guard_endpoint(view_grant, create_note, nil) }
    assert_forbidden { guard_endpoint(view_grant, revise_note, nil) }
    assert_forbidden { guard_endpoint(view_grant, remove_person, "person-1") }
    assert_nil_guard guard_endpoint(edit_grant, create_note, nil)
    assert_nil_guard guard_endpoint(edit_grant, revise_note, nil)
    assert_nil_guard guard_endpoint(edit_grant, remove_person, "person-1")
    assert_nil_guard guard_endpoint(view_grant, mark_read, "note-1")
  end

  test "an unscoped endpoint denies a grant whose owner lost access" do
    user = create_user
    root, access = create_access_recording_for(user: user, role: :admin)
    other = create_user
    grant_or_bootstrap_access!(recording: root, actor: other, role: :admin)
    endpoint = register_endpoint(:status, http_verb: :get, path: "status")

    assert_nil_guard guard_endpoint(anchor_grant(access, root), endpoint, nil)

    revoked = RecordingStudioAccessible::Services::RevokeRecordingAccess.call(
      recording: root,
      access_recording: access,
      manager_actor: other,
      allow_last_admin_removal: true
    )
    assert revoked.success?

    assert_forbidden(:view) { guard_endpoint(anchor_grant(access, root), endpoint, nil) }
  end

  test "an endpoint required_role view authorizes a view grant on post" do
    grant, page = open_grant(:view)
    endpoint = register_endpoint(
      :search_page,
      http_verb: :post,
      path: "search-pages/:id",
      recordable_type: "Page",
      required_role: :view
    )

    assert_equal page, guard_endpoint(grant, endpoint, page.id).recording
  end

  test "an endpoint include_trashed and trashed_semantics follow the endpoint role" do
    view_grant, view_page = open_grant(:view)
    edit_grant, edit_page = open_grant(:edit)
    view_page.update_column(:trashed_at, Time.current)
    edit_page.update_column(:trashed_at, Time.current)
    kept = register_endpoint(:kept_page, http_verb: :get, path: "kept-pages/:id", recordable_type: "Page")
    trashed = register_endpoint(
      :trashed_page,
      http_verb: :get,
      path: "trashed-pages/:id",
      recordable_type: "Page",
      include_trashed: true
    )
    purge = register_endpoint(
      :purge_page,
      http_verb: :post,
      path: "purge-pages/:id",
      recordable_type: "Page",
      include_trashed: true,
      trashed_semantics: :destroy
    )

    assert_missing { guard_endpoint(view_grant, kept, view_page.id) }
    assert_equal view_page, guard_endpoint(view_grant, trashed, view_page.id).recording
    assert_forbidden { guard_endpoint(view_grant, purge, view_page.id) }
    assert_equal edit_page, guard_endpoint(edit_grant, purge, edit_page.id).recording
  end

  private

  def anchor_grant(access, root)
    RecordingStudioApi::AccessGrant.new(
      api_client: nil,
      credential: nil,
      access_recording: access,
      root_recording: root
    )
  end

  def open_grant(role)
    root, access = create_access_recording_for(user: create_user, role: role)
    page = create_page_recording(root_recording: root)
    grant = RecordingStudioApi::AccessGrant.new(
      api_client: nil,
      credential: nil,
      access_recording: access,
      root_recording: root
    )
    [grant, page]
  end

  def foreign_page
    root, = create_access_recording_for(user: create_user, workspace_name: "Foreign #{SecureRandom.hex(4)}")
    create_page_recording(root_recording: root)
  end

  def boom
    ->(*) { raise "handler ran" }
  end

  def register_handler(type, action, **)
    RecordingStudioApi.register_resource_handler(type, action, handler: boom, **)
    RecordingStudioApi.resource_handler_registration(type, action)
  end

  def register_action(name, **)
    RecordingStudio.enable_capability(:echoable, on: "Page")
    RecordingStudioApi.register_capability_action(name, capability: :echoable, handler: boom, **)
    RecordingStudioApi.capability_action(name)
  end

  def register_endpoint(name, **)
    RecordingStudioApi.register_endpoint(name, handler: boom, **)
    RecordingStudioApi.registered_endpoint(name)
  end

  def guard_resource(grant, registration, action_name, id, recordable_type: "Page")
    RecordingStudioApi::HandlerGuard.resource!(
      access_grant: grant,
      recordable_type: recordable_type,
      action_name: action_name,
      id: id,
      registration: registration
    )
  end

  def guard_capability(grant, action, id, registration: nil, recordable_type: "Page", before_authorize: nil, &)
    RecordingStudioApi::HandlerGuard.capability!(
      access_grant: grant,
      api_client: nil,
      recordable_type: recordable_type,
      action: action,
      id: id,
      registration: registration,
      before_authorize: before_authorize,
      &
    )
  end

  def guard_endpoint(grant, endpoint, id)
    RecordingStudioApi::HandlerGuard.endpoint!(
      access_grant: grant,
      endpoint: endpoint,
      id: id
    )
  end

  def assert_nil_guard(result)
    assert_instance_of RecordingStudioApi::HandlerGuard::Result, result
    assert_equal %i[recording parent_recording], result.class.members
    assert_nil result.recording
    assert_nil result.parent_recording
  end

  def assert_missing(recordable_type = "Page", &)
    error = assert_raises(RecordingStudioApi::NotFoundError, &)
    assert_equal api_scope_missing_message(recordable_type), error.message
  end

  def assert_forbidden(role = :edit, &)
    error = assert_raises(RecordingStudioApi::AuthorizationError, &)
    assert_equal unauthorized_role_message(role), error.message
  end

  def type_mismatch_message(expected, actual)
    "Expected a #{expected}, but this id is a #{actual}. Pass the id of a #{expected} recording (the id returned when that resource was created or looked up)."
  end
end
