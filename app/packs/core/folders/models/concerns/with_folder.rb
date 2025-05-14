module WithFolder
  extend ActiveSupport::Concern

  included do
    has_many :documents, as: :owner, dependent: :destroy
    accepts_nested_attributes_for :documents, allow_destroy: true, reject_if: :reject_documents

    def reject_documents(attributes)
      attributes['file'].blank?
    end

    validates_associated :documents
    # The folder in which all the documents of this model should go
    belongs_to :document_folder, class_name: "Folder", dependent: :destroy, optional: true
    has_many :folders, as: :owner, dependent: :destroy
    after_commit :update_root_folder, only: %i[update]
    # Used to check if its being destroyed and not setup_document_folder
    attr_accessor :being_destroyed

    def really_destroy!(update_destroy_attributes: true)
      self.being_destroyed = true
      super
    end
  end

  def id_or_random_int
    id || rand(1..10_000)
  end

  def folder_type
    :regular
  end

  def document_list
    nil
  end

  def document_folder
    super || setup_document_folder unless being_destroyed || destroyed?
  end

  # Get or Create the folder based on folder_path
  def setup_document_folder
    if document_folder_id.blank? && folder_path.present?
      folder = Folder.where(entity_id:, full_path: folder_path).last
      # Since the folder gets created lazily, it sometimes gets called in a show action
      # So we need to ensure that its created on the primary and not replica
      ActiveRecord::Base.connected_to(role: :writing) do
        folder ||= setup_folder_from_path(folder_path)

        # Ensure the owner is setup right
        self.document_folder = folder
        save

        document_folder.owner = self
        document_folder.save

        if respond_to?(:private_folder_names)
          private_folder_names.each do |private_folder_name|
            # Create these folders, but with owner as nil so no one can see the docs except the entity
            document_folder.children.create(name: private_folder_name, entity_id: entity_id, allow_nil_owner: true)
          end
        end
      end

      folder
    end
    # self.document_folder
  end

  def folder_name
    folder_path.split("/")[-1]
  end

  # Whenever an instance is updated. Those changes might trigger folder path change
  # Triggers a job whenever any update is done.
  # Job creates the document_folder if not present-.
  # Checks if document_folder path is same as expected.
  # If not, then updates the path and descendants
  def update_root_folder
    return if respond_to?(:deleted?) && deleted?
    # Don't enque the job is document_folder is not present or path is not changed
    return if document_folder_id.blank? || document_folder&.full_path == folder_path

    if Rails.env.test?
      UpdateDocumentFolderPathJob.perform_later(self.class.name, id)
    else
      UpdateDocumentFolderPathJob.set(wait: 5.minutes).perform_later(self.class.name, id)
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
