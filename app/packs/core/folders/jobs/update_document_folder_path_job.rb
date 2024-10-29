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

      update_folder_and_descendants(folder, expected_full_path) if folder_needs_update?(folder, expected_full_path)
    end
  end

  private

  def folder_needs_update?(folder, expected_full_path)
    folder.name != expected_full_path.split("/").last || folder.full_path != expected_full_path
  end

  def update_folder_and_descendants(folder, expected_full_path)
    folder.assign_attributes(
      name: expected_full_path.split("/").last,
      full_path: expected_full_path
    )
    folder.set_defaults
    folder.save!

    update_descendants(folder)
  end

  def update_descendants(folder)
    folder.children.each do |child|
      child.set_defaults
      child.save!
      update_descendants(child)
    end
  end
end
