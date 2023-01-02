module WithFolder
  extend ActiveSupport::Concern

  included do
    has_many :folders, as: :owner, dependent: :destroy
    after_commit :rename_document_folder
  end

  def folder_type
    :system
  end

  # Get or Create the folder based on folder_path
  def document_folder
    folder = Folder.where(entity_id:, full_path: folder_path).last
    folder ||= setup_folder_from_path(folder_path)
    folder
  end

  # Given a folder path, create the folder tree
  def setup_folder_from_path(path)
    folder = nil
    parent = entity.root_folder
    path_list = path.split("/")
    path_list.each_with_index do |folder_name, _idx|
      next if folder_name.blank?

      # Check if it exists
      folder = parent.children.where(entity_id:, name: folder_name, folder_type:).first_or_create
      parent = folder
    end
    folder
  end

  # In some cases where docs are nested attributes the docs are created before the owner is created
  # Thus the document_folder does not have owner id in the path.
  # Rename the folder correctly once the owner is created
  def rename_document_folder
    if documents.present? && self.class.name != "Deal"
      folder = documents[0].folder
      folder.full_path = folder_path
      folder.name = folder_path.split("/")[-1]
      folder.save
    end
  end
end
