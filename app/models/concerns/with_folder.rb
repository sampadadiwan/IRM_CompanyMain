module WithFolder
  extend ActiveSupport::Concern

  def document_folder
    # Since the initial docs are created before the parent_folder is created
    # store them in the root folder. Move them to the main_folder post creation
    Folder.where(entity_id:, owner: self).first || Folder.first
  end

  included do
    after_create :setup_folder_details
  end

  # setup_folder_details calls setup_folder with the right params
  def setup_folder(parent_folder, main_folder_name, sub_folder_names)
    main_folder = Folder.create(entity_id:, parent: parent_folder, name: main_folder_name, folder_type: :system, owner: self)
    # Ensure subfolders are created
    sub_folder_names.each do |name|
      Folder.create(entity_id:, parent: main_folder, name:, folder_type: :system, owner: self)
    end
    # Move the docs to the right folder post creation
    documents.update(folder_id: main_folder.id)
  end
end
