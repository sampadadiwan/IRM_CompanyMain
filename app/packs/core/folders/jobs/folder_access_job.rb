class FolderAccessJob < ApplicationJob
  queue_as :serial

  def perform(folder_id, access_right_id)
    Chewy.strategy(:sidekiq) do
      ar = AccessRight.find(access_right_id)
      folder = Folder.find(folder_id)
      folder_ids = folder.descendant_ids
      folder_ids << folder.id

      # Ensure all child documents have the same access rights
      folder.entity.documents.where(folder_id: folder_ids).each_with_index do |doc, _idx|
        doc_ar = ar.dup
        doc_ar.owner = doc
        doc_ar.access_type = "Document"
        doc_ar.notify = false
        doc_ar.save
      end

      # All descendant folders too
      folder.descendants.each do |f|
        doc_ar = ar.dup
        doc_ar.owner = f
        doc_ar.notify = false
        # We dont want to retrigger this job when we save the folder access_rights
        doc_ar.save(validate: false)
      end
    end
  end
end
