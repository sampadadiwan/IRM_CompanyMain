module WithFolder
  extend ActiveSupport::Concern

  included do
    after_create :setup_folder_details
    has_many :folders, as: :owner, dependent: :destroy
  end

  def document_folder
    # Since the initial docs are created before the parent_folder is created
    # store them in the root folder. Move them to the main_folder post creation
    Folder.where(entity_id:, owner: self).first || Folder.first
  end

  def setup_folder_from_path(path)
    parent = entity.root_folder
    path.split("/").each do |folder_name|
      next if folder_name.blank?

      folder = parent.children.where(name: folder_name).first
      folder = parent.children.create(name: folder_name, entity_id:, folder_type: :system, owner: self) if folder.nil?
      parent = folder
    end
  end
end
