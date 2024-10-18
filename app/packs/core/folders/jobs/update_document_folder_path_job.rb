class UpdateDocumentFolderPathJob < ApplicationJob
  queue_as :low

  def perform(class_name, object_id)
    Chewy.strategy(:sidekiq) do
      model_class = class_name.constantize
      object = model_class.find_by(id: object_id)
      return unless object

      folder = object.document_folder
      expected_full_path = object.folder_path
      document_folder_name = expected_full_path.split("/").last
      
      update_folder(folder, expected_full_path, document_folder_name)

      update_descendants(folder)
    end
  end

  private

  def update_folder(folder, expected_full_path, document_folder_name)
    if folder.name != document_folder_name
      folder.name = document_folder_name
    end

    if folder.full_path != expected_full_path
      folder.full_path = expected_full_path
    end
    folder.set_defaults
    folder.save!
  end

  def update_descendants(folder)
    folder.descendants.find_in_batches(batch_size: 50) do |batch|
      batch.each do |child|
        child.set_defaults
        child.save!
      end
    end
  end
end
