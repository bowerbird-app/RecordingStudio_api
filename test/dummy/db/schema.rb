# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_19_010022) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "admin_roots", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
  end

  create_table "admin_sections", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_admin_sections_on_key", unique: true
  end

  create_table "folders", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "pages", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "title"
    t.datetime "updated_at", null: false
  end

  create_table "recording_studio_access_constraints", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "action", null: false
    t.string "allowed_audiences", default: [], null: false, array: true
    t.datetime "created_at", null: false
    t.index ["action"], name: "index_recording_studio_access_constraints_on_action"
  end

  create_table "recording_studio_access_invitations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "accepted_at"
    t.uuid "accepted_by_actor_id"
    t.string "accepted_by_actor_type"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.datetime "expires_at", null: false
    t.datetime "last_sent_at", null: false
    t.uuid "manager_actor_id", null: false
    t.string "manager_actor_type", null: false
    t.uuid "recording_id", null: false
    t.datetime "revoked_at"
    t.string "role", null: false
    t.string "token_digest", limit: 64, null: false
    t.datetime "updated_at", null: false
    t.index ["recording_id", "email"], name: "idx_rs_access_invitations_one_active", unique: true, where: "((accepted_at IS NULL) AND (revoked_at IS NULL))"
    t.index ["recording_id"], name: "index_recording_studio_access_invitations_on_recording_id"
    t.index ["token_digest"], name: "idx_rs_access_invitations_token_digest", unique: true
    t.check_constraint "accepted_at IS NULL OR revoked_at IS NULL", name: "access_invitations_not_accepted_and_revoked"
  end

  create_table "recording_studio_access_rules", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "action", null: false
    t.string "audience", null: false
    t.datetime "created_at", null: false
    t.index ["action"], name: "index_recording_studio_access_rules_on_action"
  end

  create_table "recording_studio_accesses", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "actor_id", null: false
    t.string "actor_type", null: false
    t.datetime "created_at", null: false
    t.uuid "depends_on_recording_id"
    t.string "role", default: "view", null: false
    t.index ["actor_type", "actor_id", "role"], name: "index_recording_studio_accesses_on_actor_and_role"
    t.index ["actor_type", "actor_id"], name: "index_recording_studio_accesses_on_actor"
    t.index ["depends_on_recording_id"], name: "index_recording_studio_accesses_on_depends_on_recording_id"
  end

  create_table "recording_studio_admin_admins", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_recording_studio_admin_admins_on_key", unique: true
  end

  create_table "recording_studio_api_admin_apis", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_recording_studio_api_admin_apis_on_key", unique: true
  end

  create_table "recording_studio_api_api_access_tokens", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "api_credential_id", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.datetime "last_used_at"
    t.datetime "revoked_at"
    t.string "token_digest", null: false
    t.string "token_prefix", null: false
    t.datetime "updated_at", null: false
    t.index ["api_credential_id"], name: "idx_on_api_credential_id_89874cbf51"
    t.index ["expires_at"], name: "index_recording_studio_api_api_access_tokens_on_expires_at"
    t.index ["token_digest"], name: "index_recording_studio_api_api_access_tokens_on_token_digest", unique: true
  end

  create_table "recording_studio_api_api_clients", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "access_recording_id"
    t.string "api_key", default: "public", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["access_recording_id"], name: "index_recording_studio_api_api_clients_on_access_recording_id", unique: true
    t.index ["api_key"], name: "index_recording_studio_api_api_clients_on_api_key"
  end

  create_table "recording_studio_api_api_credentials", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "access_recording_id", null: false
    t.uuid "api_client_id", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.datetime "last_used_at"
    t.datetime "revoked_at"
    t.string "token_digest", null: false
    t.string "token_prefix", null: false
    t.string "token_public_id", null: false
    t.datetime "updated_at", null: false
    t.index ["access_recording_id"], name: "idx_on_access_recording_id_103368144f"
    t.index ["api_client_id"], name: "index_recording_studio_api_api_credentials_on_api_client_id"
    t.index ["api_client_id"], name: "index_recording_studio_api_credentials_on_active_client", unique: true, where: "(revoked_at IS NULL)"
    t.index ["token_digest"], name: "index_recording_studio_api_api_credentials_on_token_digest", unique: true
    t.index ["token_public_id"], name: "index_recording_studio_api_api_credentials_on_token_public_id", unique: true
  end

  create_table "recording_studio_api_api_daily_latency_histogram_buckets", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "api_key", default: "public", null: false
    t.datetime "created_at", null: false
    t.date "metric_date", null: false
    t.bigint "request_count", default: 0, null: false
    t.string "request_method", null: false
    t.string "route_name", null: false
    t.integer "status_class", null: false
    t.datetime "updated_at", null: false
    t.integer "upper_bound_ms", null: false
    t.index ["api_key", "metric_date", "route_name", "request_method", "status_class", "upper_bound_ms"], name: "index_rs_api_daily_latency_histogram_on_dimensions", unique: true
    t.index ["metric_date"], name: "idx_on_metric_date_8723beba88"
  end

  create_table "recording_studio_api_api_daily_metrics", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "action_name"
    t.string "api_key", default: "public", null: false
    t.bigint "client_error_count", default: 0, null: false
    t.string "controller_name"
    t.datetime "created_at", null: false
    t.bigint "duration_count", default: 0, null: false
    t.integer "duration_max_ms", default: 0, null: false
    t.bigint "duration_sum_ms", default: 0, null: false
    t.date "metric_date", null: false
    t.bigint "rate_limited_count", default: 0, null: false
    t.bigint "request_count", default: 0, null: false
    t.string "request_method", null: false
    t.string "route_name", null: false
    t.bigint "server_error_count", default: 0, null: false
    t.integer "status_class", null: false
    t.datetime "updated_at", null: false
    t.index ["api_key", "metric_date", "route_name", "request_method", "status_class"], name: "index_rs_api_daily_metrics_on_dimensions", unique: true
    t.index ["metric_date"], name: "index_recording_studio_api_api_daily_metrics_on_metric_date"
  end

  create_table "recording_studio_api_api_request_day_summaries", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.date "day", null: false
    t.uuid "root_recording_id"
    t.string "api_key", null: false
    t.string "route_name", null: false
    t.string "request_method", null: false
    t.integer "status_code", null: false
    t.boolean "rate_limited", default: false, null: false
    t.bigint "request_count", default: 0, null: false
    t.bigint "duration_sum_ms", default: 0, null: false
    t.bigint "duration_max_ms", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["api_key", "day"], name: "index_rs_api_request_day_summaries_on_api_and_day"
    t.index ["day", "root_recording_id", "api_key", "route_name", "request_method", "status_code", "rate_limited"], name: "index_rs_api_request_day_summaries_identity", unique: true, nulls_not_distinct: true
    t.index ["root_recording_id", "day"], name: "index_rs_api_request_day_summaries_on_root_and_day"
  end

  create_table "recording_studio_api_api_request_latency_day_summaries", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.date "day", null: false
    t.uuid "root_recording_id"
    t.string "api_key", null: false
    t.string "route_name", null: false
    t.string "request_method", null: false
    t.integer "status_code", null: false
    t.integer "latency_bucket_ms", null: false
    t.bigint "request_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["api_key", "day"], name: "index_rs_api_request_latency_day_summaries_on_api_and_day"
    t.index ["day", "root_recording_id", "api_key", "route_name", "request_method", "status_code", "latency_bucket_ms"], name: "index_rs_api_request_latency_day_summaries_identity", unique: true, nulls_not_distinct: true
    t.index ["root_recording_id", "day"], name: "index_rs_api_request_latency_day_summaries_on_root_and_day"
  end

  create_table "recording_studio_api_api_settings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.boolean "api_access_enabled", default: true, null: false
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.jsonb "runtime_overrides", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_recording_studio_api_api_settings_on_key", unique: true
  end

  create_table "recording_studio_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "action", null: false
    t.uuid "actor_id"
    t.string "actor_type"
    t.datetime "created_at", null: false
    t.string "idempotency_key"
    t.uuid "impersonator_id"
    t.string "impersonator_type"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "occurred_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.uuid "previous_recordable_id"
    t.string "previous_recordable_type"
    t.uuid "recordable_id", null: false
    t.string "recordable_type", null: false
    t.uuid "recording_id", null: false
    t.index ["action", "occurred_at"], name: "index_rs_events_on_action_and_occurred_at"
    t.index ["actor_type", "actor_id", "occurred_at"], name: "index_rs_events_on_actor_and_occurred_at"
    t.index ["recording_id", "idempotency_key"], name: "index_recording_studio_events_on_recording_and_idempotency_key", unique: true, where: "(idempotency_key IS NOT NULL)"
    t.index ["recording_id", "occurred_at", "created_at"], name: "index_rs_events_on_recording_and_timeline", order: { occurred_at: :desc, created_at: :desc }
    t.index ["recording_id"], name: "index_recording_studio_events_on_recording_id"
  end

  create_table "recording_studio_logs_aggregation_runs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "aggregation_name", null: false
    t.date "day", null: false
    t.string "status", null: false
    t.text "error_message"
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["aggregation_name", "day"], name: "index_rs_logs_aggregation_runs_on_name_and_day", unique: true
  end

  create_table "recording_studio_logs_maintenance_runs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "task", null: false
    t.string "subject", null: false
    t.string "status", null: false
    t.text "details"
    t.datetime "finished_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["task", "subject", "finished_at"], name: "index_rs_logs_maintenance_runs_on_task_and_subject"
  end

  create_table "recording_studio_recordings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "parent_recording_id"
    t.uuid "recordable_id", null: false
    t.string "recordable_type", null: false
    t.uuid "root_recording_id"
    t.datetime "trashed_at"
    t.datetime "updated_at", null: false
    t.index ["parent_recording_id"], name: "index_recording_studio_recordings_on_parent_recording_id"
    t.index ["recordable_id", "root_recording_id"], name: "idx_rs_recordings_root_access", where: "(((recordable_type)::text = 'RecordingStudio::Access'::text) AND (parent_recording_id IS NOT NULL) AND (trashed_at IS NULL))"
    t.index ["recordable_type", "recordable_id", "parent_recording_id", "trashed_at"], name: "index_recording_studio_recordings_on_recordable_parent_trashed"
    t.index ["recordable_type", "recordable_id"], name: "index_recording_studio_recordings_on_recordable"
    t.index ["recordable_type", "recordable_id"], name: "index_rs_unique_root_recording_per_recordable", unique: true, where: "(parent_recording_id IS NULL)"
    t.index ["root_recording_id", "parent_recording_id"], name: "index_rs_recordings_on_root_and_parent"
    t.index ["root_recording_id", "recordable_type", "recordable_id"], name: "index_rs_recordings_on_root_and_recordable"
    t.index ["root_recording_id"], name: "index_rs_recordings_on_root_recording"
  end

  create_table "recording_studio_root_switchable_selections", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "actor_id"
    t.string "actor_type"
    t.datetime "created_at", null: false
    t.string "device_browser"
    t.string "device_key", null: false
    t.string "device_label"
    t.string "device_platform"
    t.string "device_type"
    t.datetime "last_used_at", null: false
    t.uuid "root_recording_id", null: false
    t.string "scope_key", null: false
    t.datetime "updated_at", null: false
    t.text "user_agent"
    t.index ["actor_type", "actor_id", "device_key", "scope_key"], name: "idx_rs_root_switchable_actor_device_scope", unique: true, where: "(actor_id IS NOT NULL)"
    t.index ["device_key", "scope_key"], name: "idx_rs_root_switchable_anonymous_device_scope", unique: true, where: "(actor_id IS NULL)"
    t.index ["root_recording_id"], name: "idx_rs_root_switchable_root_recording"
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "workspaces", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.datetime "updated_at", null: false
  end

  add_foreign_key "recording_studio_access_invitations", "recording_studio_recordings", column: "recording_id"
  add_foreign_key "recording_studio_api_api_access_tokens", "recording_studio_api_api_credentials", column: "api_credential_id"
  add_foreign_key "recording_studio_api_api_credentials", "recording_studio_api_api_clients", column: "api_client_id"
  add_foreign_key "recording_studio_events", "recording_studio_recordings", column: "recording_id"
  add_foreign_key "recording_studio_recordings", "recording_studio_recordings", column: "parent_recording_id"
  add_foreign_key "recording_studio_recordings", "recording_studio_recordings", column: "root_recording_id"
  add_foreign_key "recording_studio_root_switchable_selections", "recording_studio_recordings", column: "root_recording_id", on_delete: :cascade

  execute <<~SQL
    CREATE OR REPLACE VIEW recording_studio_api_api_request_day_metric_rollups AS
    SELECT
      day AS metric_date,
      api_key,
      route_name,
      request_method,
      (status_code / 100) AS status_class,
      SUM(request_count)::bigint AS request_count,
      SUM(CASE WHEN rate_limited OR status_code = 429 THEN request_count ELSE 0 END)::bigint AS rate_limited_count,
      SUM(CASE WHEN status_code BETWEEN 400 AND 499 THEN request_count ELSE 0 END)::bigint AS client_error_count,
      SUM(CASE WHEN status_code BETWEEN 500 AND 599 THEN request_count ELSE 0 END)::bigint AS server_error_count,
      SUM(request_count)::bigint AS duration_count,
      SUM(duration_sum_ms)::bigint AS duration_sum_ms,
      MAX(duration_max_ms)::integer AS duration_max_ms
    FROM recording_studio_api_api_request_day_summaries
    GROUP BY day, api_key, route_name, request_method, (status_code / 100)
  SQL
end
