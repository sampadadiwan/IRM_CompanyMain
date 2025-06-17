# Syncs data with the OpenWebUI, Run periodically to sync data with OpenWebUI
class OwSyncJob < ApplicationJob
  queue_as :low
  def perform(access_token: nil)
    access_token ||= Rails.application.credentials["OPEN_WEB_UI_ACCESS_TOKEN"]
    if access_token.present?
      Rails.logger.debug "OwSyncJob: Syncing with OpenWebUI"
      sync_entities(access_token)
    else
      Rails.logger.error "OwSyncJob: OpenWebUI access token not found. Skipping"
    end
  end

  def sync_entities(access_token)
    # Fetch entities with the permission to enable open web ui
    entities = Entity.where_permissions(:enable_ai_chat)

    entities.each do |entity|
      OpenWebUiSync.new(entity, access_token).sync
      sync_users(entity, access_token)
      sync_kpi_reports(entity, access_token)
      sync_folders(entity, access_token)
      sync_documents(entity, access_token)
    end
  end

  def sync_users(entity, access_token)
    # Fetch users with the permission to enable open web ui, which are not yet synced
    users = entity.employees
                  .where_permissions(:enable_ai_chat)
                  .where.not(id: SyncRecord.synced_ids_for(User))

    users.each do |user|
      OpenWebUiSync.new(user, access_token).sync
    end
  end

  def sync_kpi_reports(entity, access_token)
    # Fetch kpi reports which are not yet synced
    kpi_reports = entity.kpi_reports.where.not(id: SyncRecord.synced_ids_for(KpiReport))
    kpi_reports.each do |kpi_report|
      OpenWebUiSync.new(kpi_report, access_token).sync
    end
  end

  def sync_folders(entity, access_token)
    # Fetch kpi reports which are not yet synced
    folders = entity.folders.where(knowledge_base: true).where.not(id: SyncRecord.synced_ids_for(Folder))
    folders.each do |folder|
      OpenWebUiSync.new(folder, access_token).sync
    end
  end

  def sync_documents(entity, access_token)
    # Fetch documents for KpiReports which are not yet synced
    documents = entity.documents.where(owner_type: 'KpiReport')
                      .where.not(id: SyncRecord.synced_ids_for(Document))
    documents.each do |document|
      OpenWebUiSync.new(document, access_token).sync
    end

    # Fetch documents for knowledge_base Folders which are not yet synced
    documents = entity.documents.joins(:folder).where(folders: { knowledge_base: true })
                      .where.not(id: SyncRecord.synced_ids_for(Document))
    documents.each do |document|
      OpenWebUiSync.new(document, access_token).sync
    end
  end

  # rubocop:disable Rails/SkipsModelValidations
  def self.ow_docker_cmd
    doorkeeper_app = Doorkeeper::Application.find_by(name: "OpenWebUI")
    doorkeeper_app ||= Doorkeeper::Application.create!(name: "OpenWebUI",
                                                       redirect_uri: "#{ENV.fetch('OPEN_WEB_UI_URL', nil)}/oauth/oidc/callback", # match where OpenWebUI runs
                                                       scopes: "openid email profile")

    doorkeeper_app.update_column(:redirect_uri, "#{ENV.fetch('OPEN_WEB_UI_URL', nil)}/oauth/oidc/callback")

    ow_url = ENV.fetch('OPEN_WEB_UI_URL', nil)
    # Get the port number from the URL if it exists, otherwise default to 80
    ow_port = /:(\d+)/.match?(ow_url) ? ow_url.match(/:(\d+)/)[1] : 80

    docker_cmd = <<~TEXT
      docker run --rm -d --name open-webui -p #{ow_port}:8080 --add-host=localhost:host-gateway \
      -v open-webui:/app/backend/data \
      -e WEBUI_SESSION_COOKIE_SAME_SITE="none" \
      -e WEBUI_AUTH_COOKIE_SAME_SITE="none" \
      -e WEBUI_URL="#{ENV.fetch('OPEN_WEB_UI_URL', nil)}" \
      -e WEBUI_AUTH="true" \
      -e ENABLE_LOGIN_FORM="true" \
      -e ENABLE_SIGNUP="false" \
      -e ENABLE_OAUTH_SIGNUP="true" \
      -e OAUTH_CLIENT_ID="#{doorkeeper_app.uid}" \
      -e OAUTH_CLIENT_SECRET="#{doorkeeper_app.secret}" \
      -e OPENID_PROVIDER_URL="#{ENV.fetch('BASE_URL', nil)}/.well-known/openid-configuration" \
      -e OAUTH_PROVIDER_NAME="CapHive" \
      -e OAUTH_SCOPES="openid email profile" \
      -e DEFAULT_USER_ROLE="user" \
      -e ENABLE_PERSISTENT_CONFIG="false" \
      -e OPENAI_API_KEY="#{Rails.application.credentials['OPENAI_API_KEY']}" \
      -e OAUTH_REDIRECT_URI="#{doorkeeper_app.redirect_uri}" \
      ghcr.io/open-webui/open-webui:main
    TEXT

    docker_cmd.strip
  end
  # rubocop:enable Rails/SkipsModelValidations
end
