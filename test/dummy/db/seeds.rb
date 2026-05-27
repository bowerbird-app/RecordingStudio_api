# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

require "base64"
require "digest"
require "openssl"
require "securerandom"

def base64url_sha256(value)
  Base64.urlsafe_encode64(Digest::SHA256.digest(value), padding: false)
end

def ensure_recording_for(recordable:, parent_recording:)
  RecordingStudio::Recording.unscoped.find_or_create_by!(
    recordable: recordable,
    root_recording_id: parent_recording.root_recording_id,
    parent_recording_id: parent_recording.id
  )
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
    t.uuid :oauth_grant_session_id
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

def seed_api_request_logs!(admin_root_recording:, admin_access_recording:, api_credential:)
  ensure_api_request_logs_table!

  request_ids = (1..40).map { |index| format("seed-log-%03d", index) }
  RecordingStudioApi::ApiRequestLog.where(request_id: request_ids).delete_all

  request_ids.each_with_index do |request_id, index|
    occurred_at = Time.current - index.minutes
    method = index.even? ? "GET" : "POST"
    path = index.even? ? "/api/v1/recordings/#{index + 1}" : "/oauth/token"
    status_code = index % 7 == 0 ? 429 : (index % 5 == 0 ? 401 : 200)

    RecordingStudioApi::ApiRequestLog.create!(
      occurred_at: occurred_at,
      request_id: request_id,
      request_method: method,
      request_path: path,
      route_name: index.even? ? "recording" : "oauth_token",
      controller_name: index.even? ? "recording_studio_api/api/recordings" : "recording_studio_api/oauth/tokens",
      action_name: index.even? ? "show" : "create",
      status_code: status_code,
      duration_ms: 80 + (index * 9),
      rate_limited: status_code == 429,
      api_credential_id: api_credential.id,
      access_recording_id: admin_access_recording.id,
      root_recording_id: admin_root_recording.id,
      remote_ip: "192.168.10.#{(index % 20) + 10}",
      user_agent: "Seeded API Client/#{(index % 3) + 1}.0",
      error_class: status_code == 401 ? "RecordingStudioApi::Unauthorized" : nil,
      error_message: status_code == 401 ? "Seeded unauthorized response" : nil,
      request_params: {
        sample: true,
        page: index + 1,
        source: "dummy-seeds"
      }
    )
  end
end

admin_user = User.find_or_create_by!(email: "admin@admin.com") do |user|
  user.password = "Password"
  user.password_confirmation = "Password"
end

mobile_user = User.find_or_create_by!(email: "mobile-user@example.com") do |user|
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
admin_access = RecordingStudio::Access.find_or_create_by!(actor: admin_user, role: :admin)
RecordingStudio::Recording.unscoped.find_or_create_by!(
  recordable: admin_access,
  root_recording_id: admin_root_recording.id,
  parent_recording_id: admin_root_recording.id
)
admin_access_recording = RecordingStudio::Recording.unscoped.find_or_create_by!(
  recordable: admin_access,
  root_recording_id: root_recording.id,
  parent_recording_id: root_recording.id
)

Current.actor = mobile_user
mobile_access = RecordingStudio::Access.find_or_create_by!(actor: mobile_user, role: :view)
mobile_access_recording = RecordingStudio::Recording.unscoped.find_or_create_by!(
  recordable: mobile_access,
  root_recording_id: root_recording.id,
  parent_recording_id: root_recording.id
)

service_client_name = "Seed Demo Service Client"
service_credential = RecordingStudioApi::ApiCredential.joins(:api_client)
  .where(recording_studio_api_api_clients: { access_recording_id: admin_access_recording.id, name: service_client_name })
  .where(revoked_at: nil)
  .order(created_at: :desc)
  .first

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

# If a credential exists but no active token remains, rotate credential so we can
# obtain a fresh plaintext secret to issue a demonstrable token.
if service_token.nil? && service_plain_secret.nil?
  provision_result = RecordingStudioApi::Services::ProvisionApiClient.call(
    access_recording: admin_access_recording,
    name: service_client_name
  )
  raise provision_result.error unless provision_result.success?

  service_credential = provision_result.value.fetch(:credential)
  service_plain_secret = provision_result.value.fetch(:token)
end

if service_token.nil?
  issue_result = RecordingStudioApi::Services::IssueOauthAccessToken.call(
    grant_type: "client_credentials",
    client_id: service_credential.oauth_client_id,
    client_secret: service_plain_secret
  )
  raise issue_result.error unless issue_result.success?

  service_bearer_token = issue_result.value.fetch(:access_token)
  service_token = RecordingStudioApi::ApiAccessToken.order(created_at: :desc).first
end

mobile_oauth_client = RecordingStudioApi::OauthClient.find_or_initialize_by(client_identifier: "seed-mobile-public-client")
mobile_oauth_client.name = "Seed Demo Mobile App"
mobile_oauth_client.redirect_uri = "seedmobile://oauth/callback"
mobile_oauth_client.public_client = true
mobile_oauth_client.active = true
mobile_oauth_client.save!

pkce_verifier = nil
pkce_challenge = nil

active_mobile_code = RecordingStudioApi::OauthAuthorizationCode.active.where(
  oauth_client_id: mobile_oauth_client.id,
  access_recording_id: mobile_access_recording.id
).order(created_at: :desc).first

authorization_code = nil
if active_mobile_code.nil?
  pkce_verifier = SecureRandom.urlsafe_base64(64, false).first(96)
  pkce_challenge = base64url_sha256(pkce_verifier)

  authorize_result = RecordingStudioApi::Services::AuthorizeOauthClient.call(
    response_type: "code",
    client_id: mobile_oauth_client.client_identifier,
    redirect_uri: mobile_oauth_client.redirect_uri,
    code_challenge: pkce_challenge,
    code_challenge_method: "S256",
    access_recording_id: mobile_access_recording.id,
    state: "seed-mobile-state"
  )
  raise authorize_result.error unless authorize_result.success?

  authorization_code = authorize_result.value.fetch(:code)
  active_mobile_code = RecordingStudioApi::OauthAuthorizationCode.order(created_at: :desc).first
end

puts "Seeded users: admin@admin.com, mobile-user@example.com (password: Password)"
puts "Seeded admin root: #{admin_root.name}"
puts "Seeded workspace tree: #{workspace.name} -> #{folder.name} -> #{page.title}"
puts "Seeded admin root access recording: #{admin_root_recording.id}"
puts "Seeded admin access recording: #{admin_access_recording.id}"
puts "Seeded mobile access recording: #{mobile_access_recording.id}"

puts "Service OAuth client_credentials demo"
puts "  Client ID: #{service_credential.oauth_client_id}"
puts "  Client Secret (shown only when newly generated): #{service_plain_secret || '[existing credential - secret unavailable]'}"
puts "  Bearer Token (shown only when newly generated): #{service_bearer_token || '[existing active token - plaintext unavailable]'}"
puts "  Credential recording id: #{service_credential.recording&.id}"
puts "  Access token recording id: #{service_token&.recording&.id}"

puts "Mobile OAuth 2-auth demo (authorization code + PKCE)"
puts "  Public Client ID: #{mobile_oauth_client.client_identifier}"
puts "  Redirect URI: #{mobile_oauth_client.redirect_uri}"
puts "  Access recording id: #{mobile_access_recording.id}"
puts "  PKCE verifier (demo, only when newly generated): #{pkce_verifier || '[existing active code - verifier unavailable]'}"
puts "  PKCE challenge (S256): #{pkce_challenge || active_mobile_code&.code_challenge}"
puts "  Authorization code (shown only when newly generated): #{authorization_code || '[existing active code - plaintext unavailable]'}"
puts "  Authorization code recording id: #{active_mobile_code&.recording&.id}"

seed_api_request_logs!(
  admin_root_recording: admin_root_recording,
  admin_access_recording: admin_access_recording,
  api_credential: service_credential
)

puts "Seeded API request logs: #{RecordingStudioApi::ApiRequestLog.where("request_id LIKE ?", "seed-log-%").count}"

Current.actor = nil
