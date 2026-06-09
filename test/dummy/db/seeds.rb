# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

require "openssl"
require "securerandom"

def ensure_recording_for(recordable:, parent_recording:)
  RecordingStudio::Recording.unscoped.find_or_create_by!(
    recordable: recordable,
    root_recording_id: parent_recording.root_recording_id,
    parent_recording_id: parent_recording.id
  )
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

  bootstrap_access_recording!(recording: recording, actor: actor, role: effective_role, manager_actor: manager_actor)
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

def bootstrap_access_recording!(recording:, actor:, role:, manager_actor:)
  RecordingStudioAccessible::AccessCreationContext.allow do
    RecordingStudio.root_recording_or_self(recording).record(
      RecordingStudio::Access,
      actor: manager_actor,
      parent_recording: recording
    ) do |access|
      access.actor = actor
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

def seed_api_request_logs!(admin_root_recording:, admin_access_recording:, seeded_api_clients:)
  ensure_api_request_logs_table!

  RecordingStudioApi::ApiRequestLog.where("request_id LIKE ?", "seed-log-%").delete_all

  seeded_api_clients.each_with_index do |seeded_client, client_index|
    api_client = seeded_client.fetch(:api_client)
    api_credential = seeded_client.fetch(:credential)
    weekly_request_count = seeded_api_clients.length - client_index

    14.times do |week_index|
      window_start = Time.current.beginning_of_day - ((13 - week_index) * 7).days - (client_index % 4).hours

      weekly_request_count.times do |request_index|
        request_number = request_index + 1
        request_id = format(
          "seed-log-client-%02d-week-%02d-request-%02d",
          client_index + 1,
          week_index + 1,
          request_number
        )
        occurred_at = window_start + ((request_number - 1) * 45).minutes
        method = request_number.even? ? "GET" : "POST"
        path = request_number.even? ? "/api/v1/recordings/#{client_index + request_number}" : "/oauth/token"
        status_code = if request_number % 11 == 0
                        429
                      elsif request_number % 7 == 0
                        401
                      else
                        200
                      end

        RecordingStudioApi::ApiRequestLog.create!(
          occurred_at: occurred_at,
          request_id: request_id,
          request_method: method,
          request_path: path,
          route_name: request_number.even? ? "recording" : "oauth_token",
          controller_name: request_number.even? ? "recording_studio_api/api/recordings" : "recording_studio_api/oauth/tokens",
          action_name: request_number.even? ? "show" : "create",
          status_code: status_code,
          duration_ms: 80 + (client_index * 11) + (request_number * 7),
          rate_limited: status_code == 429,
          api_client_id: api_client.id,
          api_credential_id: api_credential.id,
          access_recording_id: admin_access_recording.id,
          root_recording_id: admin_root_recording.id,
          remote_ip: "192.168.10.#{((client_index * 3) + request_number) % 200}",
          user_agent: "#{api_client.name}/#{(week_index % 3) + 1}.0",
          error_class: status_code == 401 ? "RecordingStudioApi::Unauthorized" : nil,
          error_message: status_code == 401 ? "Seeded unauthorized response" : nil,
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
end

admin_user = User.find_or_create_by!(email: "admin@admin.com") do |user|
  user.password = "Password"
  user.password_confirmation = "Password"
end

admin_root = RecordingStudioAdmin::Admin.find_or_create_by!(key: "admin") do |record|
  record.name = "Admin"
end

admin_api = RecordingStudioApi::AdminApi.find_or_create_by!(key: "api") do |record|
  record.name = "Admin API"
end

workspace = Workspace.find_or_create_by!(name: "Studio Workspace")
folder = Folder.find_or_create_by!(name: "Product Docs")
page = Page.find_or_create_by!(title: "Getting Started")

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

folder_recording = ensure_recording_for(recordable: folder, parent_recording: root_recording)
ensure_recording_for(recordable: page, parent_recording: folder_recording)

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

puts "Seeded users: admin@admin.com (password: Password)"
puts "Seeded admin root: #{admin_root.name}"
puts "Seeded workspace tree: #{workspace.name} -> #{folder.name} -> #{page.title}"
puts "Seeded admin root access recording: #{admin_root_recording.id}"
puts "Seeded admin access recording: #{admin_access_recording.id}"

puts "Service OAuth client_credentials demo"
puts "  Client ID: #{service_credential.oauth_client_id}"
puts "  Client Secret (shown only when newly generated): #{service_plain_secret || '[existing credential - secret unavailable]'}"
puts "  Bearer Token (shown only when newly generated): #{service_bearer_token || '[existing active token - plaintext unavailable]'}"
puts "  Credential recording id: #{service_credential.recording&.id}"
puts "  Access token recording id: #{service_token&.recording&.id}"

seed_api_request_logs!(
  admin_root_recording: admin_root_recording,
  admin_access_recording: admin_access_recording,
  seeded_api_clients: seeded_api_clients
)

puts "Seeded API keys: #{RecordingStudioApi::ApiClient.where(access_recording_id: admin_access_recording.id, name: seeded_api_client_names).count}"
puts "Seeded API request logs: #{RecordingStudioApi::ApiRequestLog.where("request_id LIKE ?", "seed-log-%").count}"

Current.actor = nil
