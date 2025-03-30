class OpenWebUiSync
  DESCRIPTION = "Synced from CapHive".freeze

  def initialize(syncable, access_token)
    @syncable = syncable
    @client = OpenWebUiClient.new(access_token) # Replace with actual token
    @users_api = OpenWebUiUsers.new(@client)
    @auths_api = OpenWebUiAuths.new(@client)
    @knowledge_api = OpenWebUiKnowledge.new(@client)
    @files_api = OpenWebUiFiles.new(@client)
    @groups_api = OpenWebUiGroups.new(@client)
    @sync_record = SyncRecord.find_or_initialize_by(syncable: @syncable)
  end

  def sync
    Rails.logger.debug { "Syncing #{@syncable} with OpenWebUI" }
    if @syncable.respond_to?(:deleted_at) && @syncable.deleted_at.present? # Skip if deleted
      Rails.logger.debug { "Skipping sync for #{@syncable} as it is deleted" }
      return
    end

    openwebui_id =
      case @syncable.class.name
      when "User" then sync_user(@syncable)
      when "Entity" then sync_group(@syncable)
      when "Document" then sync_document(@syncable)
      when "KpiReport", "Folder" then sync_knowledge(@syncable)
      else raise "Syncing not implemented for #{@syncable.class.name}"
      end

    @sync_record.update!(openwebui_id: openwebui_id, synced_at: Time.current) if openwebui_id
  end

  def unsync
    Rails.logger.debug { "Unsyncing #{@syncable} with OpenWebUI" }
    unless @sync_record.persisted?
      Rails.logger.debug { "Skipping unsync for #{@syncable} as it is not synced" }
      return
    end

    case @syncable.class.name
    when "User" then @users_api.delete_user(@sync_record.openwebui_id)
    when "Entity" then @groups_api.delete_group(@sync_record.openwebui_id)
    when "Document" then @files_api.delete_file(@sync_record.openwebui_id)
    when "KpiReport", "Folder" then @knowledge_api.delete_knowledge(@sync_record.openwebui_id)
    else raise "Unsyncing not implemented for #{@syncable.class.name}"
    end

    @sync_record.destroy
  end

  private

  def sync_group(entity)
    group_sync_record = SyncRecord.find_by(syncable: entity)
    return group_sync_record.openwebui_id if group_sync_record && group_sync_record.openwebui_id.present?

    Rails.logger.debug { "Creating group #{entity.name}" }
    response = @groups_api.create_group({ name: entity.name, description: DESCRIPTION })
    response[:id]
  end

  def sync_user(user)
    # Check if user is already synced
    user_sync_record = SyncRecord.find_by(syncable: user)
    return user_sync_record.openwebui_id if user_sync_record && user_sync_record.openwebui_id.present?

    # Create the user
    Rails.logger.debug { "Creating user #{user.email}" }
    response = @auths_api.add(user.name, user.email, "password")
    user_openwebui_id = response[:id]

    # Add the user to the group
    add_user_to_group(user, user_openwebui_id: user_openwebui_id)

    # Return the user id
    user_openwebui_id
  end

  def sync_knowledge(kpi_report)
    knowledge_sync_record = SyncRecord.find_by(syncable: kpi_report)
    return knowledge_sync_record.openwebui_id if knowledge_sync_record && knowledge_sync_record.openwebui_id.present?

    entity_sync_record = SyncRecord.find_by(syncable: kpi_report.entity)
    entity_openwebui_id = entity_sync_record.openwebui_id
    raise "No entity sync found for #{kpi_report}" unless entity_openwebui_id

    Rails.logger.debug { "Creating knowledge #{kpi_report.name}" }

    # Create the knowledge, with read write access to this entity
    response = @knowledge_api.create_knowledge({
                                                 name: kpi_report.name, description: DESCRIPTION,
                                                 access_control: {
                                                   read: { group_ids: [entity_openwebui_id] },
                                                   write: { group_ids: [entity_openwebui_id] }
                                                 }
                                               })
    response[:id]
  end

  def sync_document(document)
    Rails.logger.debug { "Syncing document #{document.name}" }
    document_sync_record = SyncRecord.find_by(syncable: document)
    return document_sync_record.openwebui_id if document_sync_record && document_sync_record.openwebui_id.present?

    Rails.logger.debug { "Creating document #{document.name}" }
    response = {}
    document.file.download do |file|
      # Rename the file to the document.name
      file_path = file.path
      dir = File.dirname(file_path)
      ext = File.extname(file_path)
      new_name = document.name + ext
      new_path = File.join(dir, new_name)

      File.rename(file_path, new_path)

      response = @files_api.upload_file(new_path, file_metadata: { name: document.name, description: DESCRIPTION })
    end
    doc_openwebui_id = response[:id]

    # Add the document to the knowledge, which is either the owner or the folder
    # If the document is owned by a KpiReport, add it to the knowledge of the KpiReport
    # If the document is owned by a Folder, add it to the knowledge of the Folder
    knowledge_sync_record = SyncRecord.find_by(syncable: document.owner)
    knowledge_sync_record ||= SyncRecord.find_by(syncable: document.folder)

    if knowledge_sync_record
      Rails.logger.debug { "Adding document to knowledge #{knowledge_sync_record.openwebui_id}" }
      knowledge_id = knowledge_sync_record.openwebui_id
      @knowledge_api.file_add(knowledge_id, { file_id: doc_openwebui_id })
    end

    doc_openwebui_id
  end

  def add_user_to_group(user, user_openwebui_id: nil)
    # Find the group id from the user entity
    group_sync_record = SyncRecord.find_by(syncable: user.entity)
    raise "No group found for #{user.entity}" unless group_sync_record && group_sync_record.openwebui_id.present?

    group_id = group_sync_record.openwebui_id

    # If user_openwebui_id is not provided, find it from the user
    if user_openwebui_id.nil?
      user_sync_record = SyncRecord.find_by(syncable: user)
      raise "No user found #{user}" unless user_sync_record && user_sync_record.openwebui_id.present?

      user_id = user_sync_record.openwebui_id
    else
      user_id = user_openwebui_id
    end

    # Get the group details
    group = @groups_api.get_group(group_id)
    group[:user_ids] << user_id

    # Add the user to the group
    @groups_api.update_group(group_id, group)
  end
end
