class AccessRightsDeletedJob < ApplicationJob
  queue_as :low

  # This job should be called when the access right is deleted
  # This removes all the access_rights for folders and documents under the document_folder for the owner
  def perform(owner_id, owner_type, access_right_id)
    owner = owner_type.constantize.find(owner_id)
    access_right = AccessRight.with_deleted.where(id: access_right_id).first

    Chewy.strategy(:sidekiq) do
      if access_right&.deleted? && (owner.respond_to?(:document_folder) || owner_type == "Folder")
        # We need to ensure that all documents and folders have explicit access rights destroyed
        if owner.respond_to?(:document_folder)
          folder_ids = owner.document_folder.descendant_ids
          folder_ids << owner.document_folder_id
        elsif owner_type == "Folder"
          folder_ids = owner.descendant_ids
          folder_ids << owner.id
        end

        AccessRight.where(entity_id: access_right.entity_id, owner_type: "Folder", owner_id: folder_ids).where("access_rights.access_to_investor_id=? OR access_rights.user_id=?", access_right.access_to_investor_id, access_right.user_id).find_each(&:destroy)

        # Remove rights from documents
        document_ids = Document.where(entity_id: access_right.entity_id, folder_id: folder_ids).pluck(:id)
        AccessRight.where(entity_id: access_right.entity_id, owner_type: "Document", owner_id: document_ids).where("access_rights.access_to_investor_id=? OR access_rights.user_id=?", access_right.access_to_investor_id, access_right.user_id).find_each(&:destroy)
      end
    end
  end
end
