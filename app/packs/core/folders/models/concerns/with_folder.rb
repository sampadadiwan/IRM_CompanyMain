module WithFolder
  extend ActiveSupport::Concern

  included do
    has_many :documents, as: :owner, dependent: :destroy
    accepts_nested_attributes_for :documents, allow_destroy: true

    has_many :folders, as: :owner, dependent: :destroy
    # The folder in which all the documents of this model should go
    belongs_to :document_folder, class_name: "Folder", dependent: :destroy, optional: true
    # Ensure the document_folder gets renamed if required
    after_create_commit :rename_document_folder
  end

  def folder_type
    :regular
  end

  def document_folder
    super || setup_document_folder
  end

  # Get or Create the folder based on folder_path
  def setup_document_folder
    if folder_path.present?
      folder = Folder.where(entity_id:, full_path: folder_path).last
      folder ||= setup_folder_from_path(folder_path)

      # Ensure the owner is setup right
      self.document_folder = folder
      save
      document_folder.owner = self
      document_folder.save

      folder
    end
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
    if document_folder_id.present?
      document_folder.full_path = folder_path
      document_folder.name = folder_path.split("/")[-1]
      document_folder.save
    end
  end

  def document_changed(document)
    if %w[CapitalCommitment CapitalRemittance].include?(self.class.name) && !document.destroyed?
      # Give explicit access rights to the doc to this investor
      AccessRight.grant(document, investor_id)
    end
  end
end
