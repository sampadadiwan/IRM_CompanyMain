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
end
