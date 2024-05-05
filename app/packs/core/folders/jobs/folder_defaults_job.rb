class FolderDefaultsJob < ApplicationJob
  queue_as :low

  def perform(folder_id)
    Chewy.strategy(:active_job) do
      # Ensure all child documents have the same access rights
      folder = Folder.find(folder_id)
      folder.documents.update_all(printing: folder.printing, download: folder.download, orignal: folder.orignal)

      # Ensure all the descendents have the same defaults
      folder.descendants.update_all(printing: folder.printing, download: folder.download,
                                    orignal: folder.orignal)

      folder.reload
      # Documents in all sub folders now need to be updated with folder defaults
      folder.entity.documents.where(folder_id: folder.descendant_ids)
            .update_all(printing: folder.printing, download: folder.download, orignal: folder.orignal)
    end
  end
end
