class FolderAccessJob < ApplicationJob
  queue_as :serial

  # Cascaes a specific access right change down to all child documents and descendant folders.
  def perform(folder_id, access_right_id)
    Chewy.strategy(:sidekiq) do
      ar = AccessRight.find(access_right_id)
      folder = Folder.find(folder_id)
      folder_ids = folder.descendant_ids
      folder_ids << folder.id

      # Ensure all child documents have the same access rights
      folder.entity.documents.where(folder_id: folder_ids).find_each do |doc|
        ar.replicate_to(doc)
      end

      # All descendant folders too
      folder.descendants.find_each do |f|
        # We dont want to retrigger this job when we save the folder access_rights
        ar.replicate_to(f, validate: false)
      end
    end
  end
end
