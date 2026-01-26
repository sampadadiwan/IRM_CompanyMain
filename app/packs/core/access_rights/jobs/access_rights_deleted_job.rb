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

    # Initialize owner and access_right. access_right is likely soft-deleted.
    @owner = owner_type.constantize.find(owner_id)
    @access_right = AccessRight.with_deleted.find_by(id: access_right_id)

    if @access_right.nil?
      Rails.logger.warn "[AccessRightsDeletedJob] AccessRight not found with id: #{access_right_id}"
      return
    end

    Rails.logger.info "[AccessRightsDeletedJob] Found access_right: #{@access_right.id}, deleted: #{@access_right.deleted?}"

    # Use Sidekiq strategy for Chewy to handle search index updates asynchronously.
    # This ensures that search indexes for folders/documents are updated after mass deletion.
    Chewy.strategy(:sidekiq) do
      if cleanup_eligible?
        process_cleanup
      else
        Rails.logger.info "[AccessRightsDeletedJob] Conditions not met for deletion. access_right.deleted?: #{@access_right&.deleted?}, owner: #{@owner.class.name}"
      end
    end

    Rails.logger.info "[AccessRightsDeletedJob] Completed job"
  end

  private

  attr_reader :owner, :access_right

  # Cleanup only proceeds if the access right was actually deleted and we have a
  # folder-based structure to traverse (e.g., an Investor's document_folder or a Folder itself).
  def cleanup_eligible?
    access_right&.deleted? && (owner.respond_to?(:document_folder) || owner.is_a?(Folder))
  end

  # Orchestrates the identification and removal of cascading permissions.
  def process_cleanup
    folder_ids = identify_affected_folders
    remove_folder_access_rights(folder_ids)
    remove_document_access_rights(folder_ids)
  end

  # Collects IDs for the target folder and all its descendants to ensure
  # permissions are cleaned up throughout the entire subtree.
  def identify_affected_folders
    if owner.respond_to?(:document_folder)
      # For owners like Investors who have a root 'document_folder'
      folder_ids = owner.document_folder.descendant_ids
      folder_ids << owner.document_folder_id
    elsif owner.is_a?(Folder)
      # When the owner is itself a Folder
      folder_ids = owner.descendant_ids
      folder_ids << owner.id
    end
    Rails.logger.info "[AccessRightsDeletedJob] Identified Folder IDs: #{folder_ids}"
    folder_ids
  end

  # Deletes AccessRight records for the identified folders.
  # Includes cache clearing as delete_all bypasses ActiveRecord callbacks.
  def remove_folder_access_rights(folder_ids)
    Rails.logger.info "[AccessRightsDeletedJob] Destroying Folder AccessRights for entity_id: #{access_right.entity_id}, folder_ids: #{folder_ids}"

    to_delete = folder_access_rights_scope(folder_ids)
    to_delete.each(&:remove_from_user_access_rights_cache)
    to_delete.delete_all
  end

  # Deletes AccessRight records for all documents within the affected folders.
  # Documents inherit their folder's permission context, so they must be cleaned up too.
  def remove_document_access_rights(folder_ids)
    # Identify all documents within the targeted folder hierarchy.
    document_ids = Document.where(entity_id: access_right.entity_id, folder_id: folder_ids).pluck(:id)
    Rails.logger.info "[AccessRightsDeletedJob] Identified Document IDs: #{document_ids}"

    to_delete = document_access_rights_scope(document_ids)
    to_delete.each(&:remove_from_user_access_rights_cache)
    to_delete.delete_all
  end

  # Scopes AccessRights specifically for Folders within the hierarchy.
  def folder_access_rights_scope(folder_ids)
    AccessRight.where(entity_id: access_right.entity_id, owner_type: "Folder", owner_id: folder_ids)
               .merge(common_access_rights_filters)
  end

  # Scopes AccessRights specifically for Documents within the hierarchy.
  def document_access_rights_scope(document_ids)
    AccessRight.where(entity_id: access_right.entity_id, owner_type: "Document", owner_id: document_ids)
               .merge(common_access_rights_filters)
  end

  # Defines the shared criteria for identifying child or related AccessRights
  # that should be removed when the parent/source AccessRight is deleted.
  #
  # Deletes if:
  # 1. It was explicitly linked as a child (parent_access_right_id)
  # 2. It matches the same investor access (access_to_investor_id)
  # 3. It matches the same user access (user_id)
  def common_access_rights_filters
    AccessRight.where(parent_access_right_id: [access_right.id, access_right.parent_access_right_id].compact)
               .or(AccessRight.where(access_to_investor_id: access_right.access_to_investor_id))
               .or(AccessRight.where(user_id: access_right.user_id))
  end
end
