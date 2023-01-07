class FolderAccessJob < ApplicationJob
  queue_as :serial

  def perform(folder_id, access_right_id)
    Chewy.strategy(:sidekiq) do
      # Ensure all child documents have the same access rights
      ar = AccessRight.find(access_right_id)
      folder = Folder.find(folder_id)
      folder.documents.each_with_index do |doc, _idx|
        doc_ar = ar.dup
        doc_ar.owner = doc
        doc_ar.access_type = "Document"
        doc_ar.notify = false
        doc_ar.save
      end

      # Child folders too
      folder.children.find_each do |f|
        doc_ar = ar.dup
        doc_ar.owner = f
        doc_ar.notify = false
        doc_ar.save
      end
    end
  end
end
