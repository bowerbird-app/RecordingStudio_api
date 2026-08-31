# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

require "openssl"
require "securerandom"

def ensure_recording_for(recordable:, parent_recording:)
  recording = RecordingStudio::Recording.unscoped.find_or_initialize_by(recordable: recordable)
  recording.root_recording_id = parent_recording.root_recording_id
  recording.parent_recording_id = parent_recording.id
  recording.save! if recording.new_record? || recording.changed?
  recording
end

def ensure_access_recording_for(recording:, actor:, role:, manager_actor: actor)
  existing_access_recording = RecordingStudioAccessible.access_recordings_for_actor(
    recording: recording,
    actor: actor
  ).first
  effective_role = stronger_access_role(existing_role: existing_access_recording&.recordable&.role, requested_role: role)

  return revise_access_recording!(existing_access_recording, role: effective_role, manager_actor: manager_actor) if existing_access_recording.present?

  result = RecordingStudioAccessible.grant_access(
    recording: recording,
    actor: actor,
    role: effective_role,
    manager_actor: manager_actor
  )
  return result.value if result.success?

  ensure_bootstrap_owner!(recording: recording, actor: actor)
end

def ensure_bootstrap_owner!(recording:, actor:)
  result = RecordingStudioAccessible.bootstrap_owner_access!(
    recording: recording,
    actor: actor
  )
  return result.value if result.success?

  existing_access_recording = RecordingStudioAccessible.access_recordings_for_actor(
    recording: recording,
    actor: actor
  ).first
  return existing_access_recording if existing_access_recording.present?

  raise result.error
end

def stronger_access_role(existing_role:, requested_role:)
  normalized_requested_role = requested_role.to_s
  normalized_existing_role = existing_role.to_s.presence
  return normalized_requested_role if normalized_existing_role.blank?

  [normalized_existing_role, normalized_requested_role].max_by do |value|
    RecordingStudio::Access.roles.fetch(value)
  end
end

def revise_access_recording!(access_recording, role:, manager_actor:)
  return access_recording if access_recording.recordable.role.to_s == role.to_s

  RecordingStudioAccessible::AccessCreationContext.allow do
    RecordingStudio.root_recording_or_self(access_recording.parent_recording).revise(access_recording, actor: manager_actor) do |access|
      access.role = role
    end
  end
end

def ensure_api_request_logs_table!
  connection = RecordingStudioApi::ApiRequestLog.connection
  table_name = RecordingStudioApi::ApiRequestLog.table_name
  return if connection.data_source_exists?(table_name)

  connection.create_table table_name, id: :uuid do |t|
    t.datetime :occurred_at, null: false
    t.string :request_id
    t.string :request_method, null: false
    t.string :request_path, null: false
    t.string :route_name
    t.string :controller_name
    t.string :action_name
    t.integer :status_code, null: false
    t.integer :duration_ms, null: false
    t.boolean :rate_limited, null: false, default: false
    t.uuid :api_client_id
    t.uuid :api_credential_id
    t.uuid :access_recording_id
    t.uuid :root_recording_id
    t.string :remote_ip
    t.string :user_agent
    t.string :error_class
    t.string :error_message
    t.jsonb :request_params, null: false, default: {}

    t.timestamps
  end

  connection.add_index table_name, :occurred_at
  connection.add_index table_name, :request_id
  connection.add_index table_name, :status_code
  connection.add_index table_name, :request_path
  connection.add_index table_name,
                       %i[api_client_id occurred_at],
                       name: "index_rs_api_request_logs_on_client_and_time"
  connection.add_index table_name,
                       %i[api_credential_id occurred_at],
                       name: "index_rs_api_request_logs_on_credential_and_time"
end

def ensure_api_daily_metrics_tables!
  connection = RecordingStudioApi::ApiRequestLog.connection

  unless connection.data_source_exists?("recording_studio_api_api_daily_metrics")
    connection.create_table "recording_studio_api_api_daily_metrics", id: :uuid do |t|
      t.date :metric_date, null: false
      t.string :route_name, null: false
      t.string :controller_name
      t.string :action_name
      t.string :request_method, null: false
      t.integer :status_class, null: false
      t.bigint :request_count, null: false, default: 0
      t.bigint :rate_limited_count, null: false, default: 0
      t.bigint :client_error_count, null: false, default: 0
      t.bigint :server_error_count, null: false, default: 0
      t.bigint :duration_count, null: false, default: 0
      t.bigint :duration_sum_ms, null: false, default: 0
      t.integer :duration_max_ms, null: false, default: 0
      t.timestamps
    end
    connection.add_index "recording_studio_api_api_daily_metrics", %i[metric_date route_name request_method status_class], unique: true, name: "index_rs_api_daily_metrics_on_dimensions"
    connection.add_index "recording_studio_api_api_daily_metrics", :metric_date
  end

  return if connection.data_source_exists?("recording_studio_api_api_daily_latency_histogram_buckets")

  connection.create_table "recording_studio_api_api_daily_latency_histogram_buckets", id: :uuid do |t|
    t.date :metric_date, null: false
    t.string :route_name, null: false
    t.string :request_method, null: false
    t.integer :status_class, null: false
    t.integer :upper_bound_ms, null: false
    t.bigint :request_count, null: false, default: 0
    t.timestamps
  end
  connection.add_index "recording_studio_api_api_daily_latency_histogram_buckets", %i[metric_date route_name request_method status_class upper_bound_ms], unique: true, name: "index_rs_api_daily_latency_histogram_on_dimensions"
  connection.add_index "recording_studio_api_api_daily_latency_histogram_buckets", :metric_date
end

def ensure_api_client_with_credential!(access_recording:, name:, expires_at: nil, revoked_at: nil)
  deduplicate_seeded_api_clients!(name: name)

  api_client = RecordingStudioApi::ApiClient.where(name: name).detect do |client|
    client.access_recording&.recordable&.actor_type == "RecordingStudioApi::ApiClient"
  end
  credential = api_client&.credentials&.order(created_at: :desc)&.detect(&:recording)

  if credential.nil?
    provision_result = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_recording: access_recording,
      name: name,
      expires_at: expires_at
    )
    raise provision_result.error unless provision_result.success?

    api_client = provision_result.value.fetch(:api_client)
    credential = provision_result.value.fetch(:credential)
  end

  credential.update_columns(
    expires_at: expires_at,
    revoked_at: revoked_at,
    updated_at: Time.current
  )

  {
    api_client: api_client,
    credential: credential
  }
end

def seeded_api_client_status_attributes(index)
  if index <= 5
    {
      expires_at: Time.current + 6.months,
      revoked_at: 1.day.ago
    }
  elsif index.even?
    {
      expires_at: 2.weeks.ago,
      revoked_at: nil
    }
  else
    {
      expires_at: Time.current + 6.months,
      revoked_at: nil
    }
  end
end

def deduplicate_seeded_api_clients!(name:)
  clients = RecordingStudioApi::ApiClient.where(name: name).order(created_at: :desc, id: :desc).to_a
  return if clients.size <= 1

  keeper = clients.find { |candidate| candidate.credentials.where(revoked_at: nil).exists? } || clients.first
  duplicates = clients.reject { |candidate| candidate.id == keeper.id }

  duplicates.each_with_index do |duplicate, index|
    duplicate.update_columns(
      name: "#{name} (legacy #{index + 1})",
      updated_at: Time.current
    )
  end
end

def pick_weighted_index(random, weights)
  total_weight = weights.sum
  threshold = random.rand(total_weight)
  running_total = 0

  weights.each_with_index do |weight, index|
    running_total += weight
    return index if threshold < running_total
  end

  weights.length - 1
end

def seeded_api_request_scenarios(resource_recordings:)
  api_base_path = "/recording_studio_api/api/v1"
  resources_controller = "recording_studio_api/api/v1/resources"

  resource_scenarios = resource_recordings.flat_map do |recording|
    resource = RecordingStudioApi.resource_name_for(recording.recordable_type)
    resource_path = "#{api_base_path}/#{resource}"
    item_path = "#{resource_path}/#{recording.id}"

    [
      { method: "GET", path: resource_path, action: "index", controller: resources_controller, success_statuses: [200], weight: 6 },
      { method: "GET", path: item_path, action: "show", controller: resources_controller, success_statuses: [200], weight: 12 },
      { method: "POST", path: resource_path, action: "create", controller: resources_controller, success_statuses: [201], weight: 1 },
      { method: "PATCH", path: item_path, action: "update", controller: resources_controller, success_statuses: [200], weight: 1 }
    ]
  end

  resource_scenarios + [
    { method: "GET", path: api_base_path, action: "index", controller: resources_controller, success_statuses: [200], weight: 3 },
    { method: "POST", path: "/recording_studio_api/oauth/token", action: "token", controller: "recording_studio_api/oauth", success_statuses: [200], weight: 2 }
  ]
end

def seed_api_request_logs!(admin_root_recording:, admin_access_recording:, resource_recordings:, seeded_api_clients:)
  ensure_api_request_logs_table!
  ensure_api_daily_metrics_tables!
  now = Time.current
  request_scenarios = seeded_api_request_scenarios(resource_recordings: resource_recordings)
  scenario_weights = request_scenarios.map { |scenario| scenario.fetch(:weight) }

  RecordingStudioApi::ApiRequestLog.where("request_id LIKE ?", "seed-log-%").delete_all

  seeded_api_clients.each_with_index do |seeded_client, client_index|
    api_client = seeded_client.fetch(:api_client)
    api_credential = seeded_client.fetch(:credential)
    baseline_weekly_request_count = seeded_api_clients.length - client_index
    weekday_weights = [24, 27, 22, 19, 16, 9, 7]

    14.times do |week_index|
      week_seed = ((client_index + 1) * 10_000) + ((week_index + 1) * 97)
      week_random = Random.new(week_seed)
      week_start = (Date.current.beginning_of_week - (13 - week_index).weeks).beginning_of_day
      variability = ((week_random.rand - 0.5) * (baseline_weekly_request_count * 0.5)).round
      weekly_request_count = [baseline_weekly_request_count + variability, 1].max

      weekly_request_count.times do |request_index|
        request_number = request_index + 1
        request_seed = (week_seed * 1000) + request_number
        request_random = Random.new(request_seed)
        day_offset = pick_weighted_index(request_random, weekday_weights)
        occurred_at = week_start + day_offset.days + (7 + request_random.rand(13)).hours + request_random.rand(60).minutes + request_random.rand(60).seconds
        occurred_at = now - request_random.rand(6.hours).seconds if occurred_at > now
        scenario = request_scenarios.fetch(pick_weighted_index(request_random, scenario_weights))
        status_roll = request_random.rand(100)
        status_code = if status_roll < 72
                        scenario.fetch(:success_statuses).sample(random: request_random)
                      elsif status_roll < 82
                        401
                      elsif status_roll < 88
                        403
                      elsif status_roll < 94
                        422
                      elsif status_roll < 98
                        429
                      else
                        500
                      end
        request_id = format(
          "seed-log-client-%02d-week-%02d-request-%02d",
          client_index + 1,
          week_index + 1,
          request_number
        )

        RecordingStudioApi::ApiRequestLog.create!(
          occurred_at: occurred_at,
          request_id: request_id,
          request_method: scenario.fetch(:method),
          request_path: scenario.fetch(:path),
          route_name: scenario.fetch(:controller),
          controller_name: scenario.fetch(:controller),
          action_name: scenario.fetch(:action),
          status_code: status_code,
          duration_ms: 75 + (client_index * 9) + request_random.rand(250),
          rate_limited: status_code == 429,
          api_client_id: api_client.id,
          api_credential_id: api_credential&.id,
          access_recording_id: admin_access_recording.id,
          root_recording_id: admin_root_recording.id,
          remote_ip: "192.168.10.#{((client_index * 5) + request_random.rand(220)) % 220}",
          user_agent: "#{api_client.name}/#{request_random.rand(1..3)}.#{request_random.rand(0..9)}",
          error_class: ([401, 429, 500].include?(status_code) ? "RecordingStudioApi::RequestFailure" : nil),
          error_message: (status_code >= 400 ? "Seeded #{status_code} response" : nil),
          request_params: {
            sample: true,
            page: request_number,
            source: "dummy-seeds",
            api_key_name: api_client.name
          }
        )
      end
    end
  end

  RecordingStudioApi::ApiRequestLog.distinct.pluck(Arel.sql("DATE(occurred_at)")).each do |metric_date|
    RecordingStudioApi::Services::AggregateApiRequestLogMetrics.call(metric_date: metric_date)
  end
  RecordingStudioApi::Services::PruneApiRequestLogs.call
end

admin_user = User.find_or_create_by!(email: "admin@admin.com") do |user|
  user.password = "Password"
  user.password_confirmation = "Password"
end

admin_root = AdminRoot.find_or_create_by!(name: "Admin")

admin_api = RecordingStudioApi::AdminApi.find_or_create_by!(key: "api") do |record|
  record.name = "Admin API"
end

workspace = Workspace.find_or_create_by!(name: "Studio Workspace")
folders = ["Product Docs", "Release Notes"].map { |name| Folder.find_or_create_by!(name: name) }
pages = ["Getting Started", "Production Checklist"].map { |title| Page.find_or_create_by!(title: title) }

admin_root_recording = RecordingStudio::Recording.unscoped.find_or_create_by!(
  recordable: admin_root,
  parent_recording_id: nil
)

RecordingStudio::Recording.unscoped.find_or_create_by!(
  recordable: admin_api,
  root_recording_id: admin_root_recording.id,
  parent_recording_id: admin_root_recording.id
)

root_recording = RecordingStudio::Recording.unscoped.find_or_create_by!(
  recordable: workspace,
  parent_recording_id: nil
)

folder_recordings = folders.map { |folder| ensure_recording_for(recordable: folder, parent_recording: root_recording) }
page_recordings = pages.map { |page| ensure_recording_for(recordable: page, parent_recording: root_recording) }
folder_recording = folder_recordings.first
page_recording = page_recordings.first

Current.actor = admin_user
ensure_access_recording_for(
  recording: admin_root_recording,
  actor: admin_user,
  role: :admin,
  manager_actor: admin_user
)
admin_access_recording = ensure_access_recording_for(
  recording: root_recording,
  actor: admin_user,
  role: :admin,
  manager_actor: admin_user
)

second_workspace = Workspace.find_or_create_by!(name: "Docs Workspace")
second_root_recording = RecordingStudio::Recording.unscoped.find_or_create_by!(
  recordable: second_workspace,
  parent_recording_id: nil
)
ensure_access_recording_for(
  recording: second_root_recording,
  actor: admin_user,
  role: :admin,
  manager_actor: admin_user
)

seeded_oauth_client = RecordingStudioApi::OauthClient.find_or_initialize_by(client_id: "rsapi_oc_seed_demo_app")
if seeded_oauth_client.new_record?
  seeded_oauth_client.assign_attributes(
    name: "Seed Demo App",
    confidential: false,
    redirect_uris: ["http://127.0.0.1/callback"],
    api_key: "public"
  )
  seeded_oauth_client.save!
end

seeded_oauth_authorization = RecordingStudioApi::OauthAuthorization.find_by(
  oauth_client: seeded_oauth_client,
  manager_actor: admin_user,
  revoked_at: nil
)
if seeded_oauth_authorization.nil?
  oauth_grant = RecordingStudioApi::Services::CreateOauthAuthorization.call(
    oauth_client: seeded_oauth_client,
    manager_actor: admin_user,
    access_recording: admin_access_recording,
    role: "view",
    redirect_uri: "http://127.0.0.1/callback",
    code_challenge: RecordingStudioApi::Pkce.s256_challenge("A" * 43),
    code_challenge_method: "S256"
  )
  raise oauth_grant.error unless oauth_grant.success?

  seeded_oauth_authorization = oauth_grant.value.fetch(:authorization)
end

Current.actor = admin_user
service_client_name = "Seed Demo Service Client"
deduplicate_seeded_api_clients!(name: service_client_name)
service_client = RecordingStudioApi::ApiClient.where(name: service_client_name).detect do |client|
  client.access_recording&.recordable&.actor_type == "RecordingStudioApi::ApiClient"
end
service_credential = service_client&.credentials&.where(revoked_at: nil)&.order(created_at: :desc)&.first

service_plain_secret = nil
if service_credential.nil?
  provision_result = RecordingStudioApi::Services::ProvisionApiClient.call(
    access_recording: admin_access_recording,
    name: service_client_name
  )
  raise provision_result.error unless provision_result.success?
  service_credential = provision_result.value.fetch(:credential)
  service_plain_secret = provision_result.value.fetch(:token)
end

service_token = RecordingStudioApi::ApiAccessToken.active.where(api_credential_id: service_credential.id).order(created_at: :desc).first
service_bearer_token = nil

if service_token.nil? && service_plain_secret.present?
  issue_result = RecordingStudioApi::Services::IssueOauthAccessToken.call(
    grant_type: "client_credentials",
    client_id: service_credential.oauth_client_id,
    client_secret: service_plain_secret
  )
  raise issue_result.error unless issue_result.success?

  service_bearer_token = issue_result.value.fetch(:access_token)
  service_token = RecordingStudioApi::ApiAccessToken.order(created_at: :desc).first
end

seeded_api_client_names = [service_client_name] + (1..49).map { |index| format("Seed API Key %02d", index) }
seeded_api_clients = seeded_api_client_names.map.with_index do |name, index|
  if name == service_client_name
    {
      api_client: service_credential.api_client,
      credential: service_credential
    }
  else
    status_attributes = seeded_api_client_status_attributes(index)

    ensure_api_client_with_credential!(
      access_recording: admin_access_recording,
      name: name,
      expires_at: status_attributes.fetch(:expires_at),
      revoked_at: status_attributes.fetch(:revoked_at)
    )
  end
end

seeded_client_ids = seeded_api_clients.map { |entry| entry.fetch(:api_client).id }

supplemental_seeded_api_clients = RecordingStudioApi::ApiClient
  .where(access_recording_id: admin_access_recording.id)
  .where.not(id: seeded_client_ids)
  .order(created_at: :asc, id: :asc)
  .map do |api_client|
    {
      api_client: api_client,
      credential: api_client.credentials.order(created_at: :desc).detect(&:recording)
    }
  end

seeded_api_clients.concat(supplemental_seeded_api_clients)

service_name_variant_clients = RecordingStudioApi::ApiClient
  .where("name ILIKE ?", "#{service_client_name}%")
  .where.not(id: seeded_api_clients.map { |entry| entry.fetch(:api_client).id })
  .order(created_at: :asc, id: :asc)
  .map do |api_client|
    {
      api_client: api_client,
      credential: api_client.credentials.order(created_at: :desc).detect(&:recording)
    }
  end

seeded_api_clients.concat(service_name_variant_clients)

puts "Seeded users: admin@admin.com (password: Password)"
puts "Seeded admin root: #{admin_root.name}"
puts "Seeded workspace children: #{workspace.name} -> folders: #{folders.map(&:name).join(', ')}; pages: #{pages.map(&:title).join(', ')}"
puts "Seeded admin root access recording: #{admin_root_recording.id}"
puts "Seeded admin access recording: #{admin_access_recording.id}"
puts "Seeded OAuth app: #{seeded_oauth_client.name} (#{seeded_oauth_client.client_id})"
puts "Seeded connected app authorization: #{seeded_oauth_authorization.id}"

puts "Service OAuth client_credentials demo"
puts "  Client ID: #{service_credential.oauth_client_id}"
puts "  Client Secret (shown only when newly generated): #{service_plain_secret || '[existing credential - secret unavailable]'}"
puts "  Bearer Token (shown only when newly generated): #{service_bearer_token || '[existing active token - plaintext unavailable]'}"
puts "  Credential recording id: #{service_credential.recording&.id}"
puts "  Access token recording id: #{service_token&.recording&.id}"

seed_api_request_logs!(
  admin_root_recording: admin_root_recording,
  admin_access_recording: admin_access_recording,
  resource_recordings: [root_recording, folder_recording, page_recording],
  seeded_api_clients: seeded_api_clients
)

puts "Seeded API keys: #{RecordingStudioApi::ApiClient.where(name: seeded_api_client_names).count}"
puts "Seeded API request logs: #{RecordingStudioApi::ApiRequestLog.where("request_id LIKE ?", "seed-log-%").count}"

Current.actor = nil
