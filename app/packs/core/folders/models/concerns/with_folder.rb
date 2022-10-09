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
    # main_folder = Folder.create(entity_id:, parent: parent_folder, name: main_folder_name, folder_type: :system, owner: self)

    main_folder = create_if_not_exist(main_folder_name, entity_id, parent_folder, :system)
    # Ensure subfolders are created
    sub_folder_names.each do |name|
      # Folder.create(entity_id:, parent: main_folder, name:, folder_type: :system, owner: self)
      create_if_not_exist(name, entity_id, main_folder, :system)
    end
    # Move the docs to the right folder post creation
    documents.update(folder_id: main_folder.id)
  end

  private

  def create_if_not_exist(name, entity_id, parent, folder_type)
    Rails.logger.debug { "Creating folder #{name} with parent #{parent}" }
    existing = Folder.where(name:, entity_id:, parent_folder_id: parent.id, folder_type:).first
    existing || Folder.create!(name:, entity_id:, parent_folder_id: parent.id, folder_type:, owner: self)
  end
end
