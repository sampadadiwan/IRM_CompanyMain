class UpdateDocumentFolderPathJob < ApplicationJob
  queue_as :serial

  def perform(class_name, owner_id)
    Chewy.strategy(:sidekiq) do
      model_class = class_name.constantize
      owner = model_class.find_by(id: owner_id)
      return unless owner

      folder = owner.document_folder
      return if folder.nil?
      expected_full_path = owner.folder_path
      document_folder_name = expected_full_path.split("/").last

      update_folder(folder, expected_full_path, document_folder_name)

      update_descendants(folder)
    end
  end

  private

  def update_folder(folder, expected_full_path, document_folder_name)
    folder.name = document_folder_name if folder.name != document_folder_name

    folder.full_path = expected_full_path if folder.full_path != expected_full_path
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
