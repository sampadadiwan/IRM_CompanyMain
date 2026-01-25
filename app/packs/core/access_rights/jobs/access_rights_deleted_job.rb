class AccessRightsDeletedJob < ApplicationJob
  queue_as :low

  # Triggered upon AccessRight deletion to clean up inherited/cascading permissions.
  # It identifies all sub-folders and documents under the specified owner and removes
  # their corresponding AccessRight records that were linked to the deleted one.
  #
  # @param owner_id [Integer] ID of the object owning the document structure (e.g., Investor, Folder)
  # @param owner_type [String] Class name of the owner
  # @param access_right_id [Integer] ID of the (soft-)deleted AccessRight record
  def perform(owner_id, owner_type, access_right_id)
    Rails.logger.info "[AccessRightsDeletedJob] Starting job for owner_id: #{owner_id}, owner_type: #{owner_type}, access_right_id: #{access_right_id}"

    # Initialize the owner object and fetch the deleted AccessRight record.
    # We use .with_deleted because the record is likely already soft-deleted.
    owner = owner_type.constantize.find(owner_id)
    access_right = AccessRight.with_deleted.where(id: access_right_id).first

    if access_right.nil?
      Rails.logger.warn "[AccessRightsDeletedJob] AccessRight not found with id: #{access_right_id}"
      return
    end

    Rails.logger.info "[AccessRightsDeletedJob] Found access_right: #{access_right.id}, deleted: #{access_right.deleted?}"

    # Use Sidekiq strategy for Chewy to handle search index updates asynchronously
    Chewy.strategy(:sidekiq) do
      # Proceed only if the access right is confirmed deleted and we have a valid folder structure to traverse
      if access_right&.deleted? && (owner.respond_to?(:document_folder) || owner_type == "Folder")

        # Step 1: Identify all affected folders (the root folder plus all its descendants)
        if owner.respond_to?(:document_folder)
          # For owners like Investors who have a root 'document_folder'
          folder_ids = owner.document_folder.descendant_ids
          folder_ids << owner.document_folder_id
          Rails.logger.info "[AccessRightsDeletedJob] Processing via owner.document_folder. Folder IDs: #{folder_ids}"
        elsif owner_type == "Folder"
          # When the owner is itself a Folder
          folder_ids = owner.descendant_ids
          folder_ids << owner.id
          Rails.logger.info "[AccessRightsDeletedJob] Processing via Folder owner. Folder IDs: #{folder_ids}"
        end

        # Step 2: Remove explicit AccessRights for the identified folders
        # These are child access rights that were specifically tied to the deleted parent
        Rails.logger.info "[AccessRightsDeletedJob] Destroying Folder AccessRights for entity_id: #{access_right.entity_id}, folder_ids: #{folder_ids}, parent_access_right_id: #{access_right.id}"

        to_delete = AccessRight.where(entity_id: access_right.entity_id, owner_type: "Folder", owner_id: folder_ids, parent_access_right_id: [access_right.id, access_right.parent_access_right_id].compact)

        # Because we are not running callbacks on delete_all, we need to manually clear caches
        to_delete.each(&:remove_from_user_access_rights_cache)

        # Find and destroy all AccessRights for the folders that were inherited from the deleted access right
        to_delete.delete_all

        # Step 3: Remove explicit AccessRights for all documents within those folders
        document_ids = Document.where(entity_id: access_right.entity_id, folder_id: folder_ids).pluck(:id)
        Rails.logger.info "[AccessRightsDeletedJob] Found Document IDs: #{document_ids}"

        Rails.logger.info "[AccessRightsDeletedJob] Destroying Document AccessRights for entity_id: #{access_right.entity_id}, document_ids: #{document_ids}, parent_access_right_id: #{access_right.id}"
        # Find and destroy all AccessRights for the documents that were inherited from the deleted access right
        doc_access_rights_to_delete = AccessRight.where(entity_id: access_right.entity_id, owner_type: "Document", owner_id: document_ids,
                                                        parent_access_right_id: [access_right.id, access_right.parent_access_right_id].compact)

        # Because we are not running callbacks on delete_all, we need to manually clear caches
        doc_access_rights_to_delete.each(&:remove_from_user_access_rights_cache)

        doc_access_rights_to_delete.delete_all
      else
        Rails.logger.info "[AccessRightsDeletedJob] Conditions not met for deletion. access_right.deleted?: #{access_right&.deleted?}, owner.respond_to?(:document_folder): #{owner.respond_to?(:document_folder)}, owner_type: #{owner_type}"
      end
    end
    Rails.logger.info "[AccessRightsDeletedJob] Completed job"
  end
end
