module WithFolder
  extend ActiveSupport::Concern

  included do
    has_many :documents, as: :owner, dependent: :destroy
    accepts_nested_attributes_for :documents, allow_destroy: true, reject_if: :reject_documents

    def reject_documents(attributes)
      attributes['file'].blank?
    end

    validates_associated :documents
    has_many :folders, as: :owner, dependent: :destroy
    # The folder in which all the documents of this model should go
    belongs_to :document_folder, class_name: "Folder", dependent: :destroy, optional: true

    # This is required as there is a circular dependency between Folder and owner
    # So if we try and destroy the owner, it will try and destroy the folder which will fail as the owner will be invalid reference.
    before_destroy :update_folder_reference
    def update_folder_reference
      # rubocop:disable Rails/SkipsModelValidations
      document_folder.update_column(:owner_id, nil) if document_folder.present?
      # rubocop:enable Rails/SkipsModelValidations
    end
  end

  def folder_type
    :regular
  end

  def document_list
    nil
  end

  def document_folder
    super || setup_document_folder
  end

  # Get or Create the folder based on folder_path
  def setup_document_folder
    if folder_path.present? && !destroyed?
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

  def folder_name
    folder_path.split("/")[-1]
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

  def document_changed(document)
    grant_access_rights_to_investor(document)
  end

  def grant_access_rights_to_investor(document)
    if %w[CapitalCommitment CapitalRemittance CapitalDistributionPayment InvestorKyc IndividualKyc NonIndividualKyc Offer Interest].include?(self.class.name) && document.id.present?
      # Check if the doc exists
      doc = Document.where(id: document.id).first
      # Give explicit access rights to the doc to this investor
      # This is so that it becomes visible in the doc explorer
      AccessRight.grant(document, investor_id) if doc.present?
    end
  end

  def get_or_create_folder(name, access_right = nil)
    folder = document_folder.children.where(name:).first.presence
    if folder.nil?
      folder = document_folder.children.create(entity_id:, owner: self, name:, parent: document_folder)
      if access_right
        access_right.owner = folder
        access_right.save
      end
    end
    folder
  end
end
