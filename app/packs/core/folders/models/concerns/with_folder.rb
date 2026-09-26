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
    # `on:`, not `only:` -- ActiveRecord's after_commit only understands `on:`, so the
    # `only: %i[update]` this used to carry was silently ignored and the hook ran on every
    # commit, create and destroy included.
    after_commit :update_root_folder, on: %i[update]
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
    path = persisted_folder_path
    return if document_folder_id.present? || path.blank?

    folder = Folder.where(entity_id:, full_path: path).last
    # Since the folder gets created lazily, it sometimes gets called in a show action
    # So we need to ensure that its created on the primary and not replica
    ActiveRecord::Base.connected_to(role: :writing) do
      # Before minting a brand new folder, adopt one this record already owns (see
      # #adoptable_owned_folder). Without this, a record whose document_folder_id never got
      # written ends up owning one folder per visit.
      folder ||= adoptable_owned_folder(path)
      folder ||= setup_folder_from_path(path)

      # Ensure the owner is setup right
      link_document_folder(folder)

      document_folder.owner = self
      document_folder.save

      if respond_to?(:private_folder_names)
        private_folder_names.each do |private_folder_name|
          # Create these folders, but with owner as nil so no one can see the docs except the entity
          document_folder.children.create(name: private_folder_name, entity_id: entity_id, private: true)
        end
      end
    end

    folder
  end

  # Writes the owner -> folder pointer.
  #
  # This used to be a bare `save`, and that was the root cause of the "Full path combination
  # must be unique" storm: many owners are created in a deliberately invalid state (an
  # InvestorKyc is saved with `validate: false` while PAN/address/bank details are still
  # blank), so the `save` here returned false, nobody checked, and document_folder_id stayed
  # NULL -- while the Folder row itself was created and stamped with `owner`. Every later
  # touch then saw a blank document_folder_id and created *another* folder for the same
  # owner. When the record finally became valid it latched onto one of them, and the first
  # rename after that tried to move it onto its twin's path, which
  # Folder's `full_path` + owner + entity uniqueness rule forbids -- forever, on every edit.
  #
  # update_column, not save: this pointer is bookkeeping and must not depend on the owner
  # passing validation. It also writes exactly one column, so a half-filled form sitting in
  # memory on a failed submit cannot be persisted as a side effect (a `save(validate: false)`
  # here would write all of it).
  def link_document_folder(folder)
    self.document_folder = folder

    # A new record has no row to update yet; its own save writes the foreign key.
    persisted? ? update_column(:document_folder_id, folder.id) : save
  end

  # A folder that this record already owns in the place the new folder would go.
  #
  # Defence in depth for the bug described on #link_document_folder: if a stale duplicate is
  # already lying around, reuse it instead of adding a third. Deliberately scoped to direct
  # children of the expected parent, so the data room / private / "Deal Documents" folders
  # that live *under* document_folder (and inherit its owner via Folder#set_parent_permissions)
  # are never mistaken for the document folder itself.
  def adoptable_owned_folder(path)
    return nil unless persisted?

    parent_path = path.split("/")[0...-1].join("/").presence || "/"
    parent = Folder.where(entity_id:, full_path: parent_path).last
    return nil if parent.nil?

    parent.children.where(entity_id:, owner_id: id, owner_type: self.class.base_class.name, folder_type:).order(:id).first
  end

  # folder_path built from what is actually in the database.
  #
  # #folder_path reads attributes off the instance, so during a failed form submit it reflects
  # what the user typed rather than what was stored -- that is how folder "SP Family Trust"
  # came to exist a day before the KYC's full_name was ever changed to it. Unsaved input must
  # not name a folder; once the edit really commits, update_root_folder enqueues the rename.
  def persisted_folder_path
    return folder_path unless persisted? && has_changes_to_save?

    # base_class so an in-memory STI type change (InvestorKyc#set_investor_name rewrites
    # `type` before save) cannot make this lookup miss its own row.
    self.class.base_class.find_by(id:)&.folder_path || folder_path
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

    # Do not delay the job as a new folder with the updated path gets created and when the job runs to update the original folders path it fails the full path uniqueness validation
    # Two folders then exist for the same object
    UpdateDocumentFolderPathJob.perform_later(self.class.name, id)
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
