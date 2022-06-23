module WithFolder
  extend ActiveSupport::Concern

  def parent_folder
    Folder.where(entity_id:, level: 1, name: parent_folder_name).first
  end

  def owner_folder
    # Since the initial docs are created before the parent_folder is created
    # store them in the parent_folder. Move them to the main_folder post creation
    Folder.where(entity_id:, owner: self).first || parent_folder
  end

  included do
    after_create :setup_folder
  end

  def setup_folder
    main_folder = Folder.create(entity_id:, parent: parent_folder, name: main_folder_name, folder_type: :system, owner: self)
    # Ensure subfolders are created
    sub_folder_names.each do |name|
      Folder.create(entity_id:, parent: main_folder, name:, folder_type: :system, owner: self)
    end
    # Move the docs to the right folder post creation
    documents.update(folder_id: main_folder.id)
  end

  # Override
  def sub_folder_names
    []
  end

  def main_folder_name
    name
  end

  def parent_folder_name
    self.class.name.pluralize.titleize
  end
end
