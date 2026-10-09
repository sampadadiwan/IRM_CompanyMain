class Folder < ApplicationRecord
  include Trackable.new
  include Workflowable
  # Changed: Replaced direct has_one :nda_config with WithNda concern.
  # Why: NdaConfig is now polymorphic — WithNda encapsulates the association and
  # nda_required? predicate so any model (Folder, IO, etc.) can include it.
  include WithNda

  # Auto-assignment rules use the folder's search fields (folders have no custom fields)
  workflow_rule_fields

  has_ancestry orphan_strategy: :destroy, touch: true

  # Changed: Added NDA_INHERITANCE_MODES constant and validation for nda_inheritance_mode column.
  # Why: Module 5 adds three-way inheritance mode to each folder. The constant is used by
  # the validation and by views rendering mode selectors. DB default is "inherit" — folders
  # look up the tree unless explicitly set to "own" (has config) or "opt_out" (no NDA).
  NDA_INHERITANCE_MODES = %w[inherit own opt_out].freeze

  update_index('folder') { self if index_record? }

  enum :folder_type, %i[regular system]

  belongs_to :parent, class_name: "Folder", optional: true
  belongs_to :entity
  belongs_to :owner, polymorphic: true, optional: true
  has_many :documents, dependent: :destroy
  accepts_nested_attributes_for :documents, allow_destroy: true

  has_many :access_rights, as: :owner, dependent: :destroy

  validates :name, presence: true
  validates :nda_inheritance_mode, inclusion: { in: NDA_INHERITANCE_MODES }
  normalizes :name, with: ->(name) { name.strip }

  validates :full_path, uniqueness: { scope: %i[owner_id owner_type entity_id], message: "combination must be unique" }

  before_create :set_defaults
  after_create :set_parent_permissions, if: :parent

  scope :for, ->(user) { where("folders.entity_id=?", user.entity_id).order(:full_path) }
  scope :for_entity, ->(entity) { where("folders.entity_id=?", entity.id).order(:full_path) }
  scope :private_folders, -> { where("folders.private=?", true) }

  # @return [Boolean] Whether this folder is inside a Data Room hierarchy.
  def in_data_room?
    return @in_data_room if defined?(@in_data_room)

    @in_data_room = data_room_root? || ancestors.any? { |a| a.name == "Data Room" && a.parent&.system? }
  end

  # @return [Boolean] Whether this folder is the root of a Data Room.
  def data_room_root?
    name == "Data Room" && parent&.system?
  end

  # Changed: Added convenience predicates for NDA inheritance mode.
  # Why: Controllers and views need to branch on inheritance mode without comparing strings.
  # @return [Boolean] Whether this folder inherits its parent's NDA config.
  def nda_inheriting?
    nda_inheritance_mode == "inherit"
  end

  # @return [Boolean] Whether this folder has its own NDA config.
  def nda_own?
    nda_inheritance_mode == "own"
  end

  # @return [Boolean] Whether this folder explicitly opts out of NDA, even if parent has one.
  def nda_opted_out?
    nda_inheritance_mode == "opt_out"
  end

  # Changed: Override nda_required? from WithNda to delegate to effective_nda_config.
  # Why: With inheritance, a folder may not have its own config but still require NDA via
  # a parent. effective_nda_config walks the tree and returns the resolved config.
  # @return [Boolean] Whether this folder requires NDA acceptance for access.
  def nda_required?
    effective_nda_config&.enabled? || false
  end

  # Changed: Added effective_nda_config method that resolves NDA via ancestry walk.
  # Why: A folder with mode "inherit" has no config of its own — it must walk up ancestors
  # until it finds one with mode "own" (or hits "opt_out" / root). Memoized per instance.
  # @return [NdaConfig, nil] The resolved NDA config, or nil if none applies.
  def effective_nda_config
    return @effective_nda_config if defined?(@effective_nda_config)

    @effective_nda_config = resolve_effective_nda[0]
  end

  # Changed: Added nda_source_folder method to return the folder owning the effective NDA.
  # Why: The UI shows "(Inherited from: <folder name>)" next to lock icons.
  # @return [Folder, nil] The folder that owns the effective NDA config, or nil.
  def nda_source_folder
    return @nda_source_folder if defined?(@nda_source_folder)

    @nda_source_folder = resolve_effective_nda[1]
  end

  def set_defaults
    if parent
      self.level = parent.level + 1
      self.full_path = level == 1 ? "#{parent.full_path}#{name}" : "#{parent.full_path}/#{name}"
      self.folder_type ||= :regular
    else
      self.level = 0
      self.full_path = "/"
      self.folder_type = :system
    end
  end

  def to_s
    name
  end

  # workflow_display_name and workflow_url use Workflowable defaults (to_s → name, folder_path).
  # Override workflow_attachable_files because folders have documents to attach.
  def workflow_attachable_files
    documents.to_a
  end

  # Inherits access rights from the parent folder upon creation.
  def set_parent_permissions
    parent.access_rights.each do |parent_ar|
      parent_ar.replicate_to(self)

      # Ensure any documents in this folder also get the same access rights
      documents.find_each do |doc|
        parent_ar.replicate_to(doc)
      end
    end

    # If we have an owner for the parent and none for the child
    if parent.owner && owner.nil?
      self.owner = parent.owner
      self.private = parent.private
      save
    end
  end

  # This is triggered when the access rights change
  def access_rights_changed(access_right)
    access_right = AccessRight.where(id: access_right.id).first
    FolderAccessJob.perform_later(id, access_right.id) if access_right&.cascade && (documents.any? || children.any?)
  end

  # This is required when really destroying a folder.
  # We need to remove circular references, else the destroy will fail
  before_real_destroy :remove_owner_reference
  def remove_owner_reference
    if owner.respond_to?(:document_folder_id) && owner.document_folder_id == id
      owner.update_column(:document_folder_id, nil)
    elsif owner.respond_to?(:data_room_folder_id) && owner.data_room_folder_id == id
      owner.update_column(:data_room_folder_id, nil)
    end
    reload
  end

  after_commit :folder_changed, unless: :destroyed?
  def folder_changed
    FolderDefaultsJob.perform_later(id) if saved_change_to_orignal? || saved_change_to_printing? || saved_change_to_download?
  end

  def self.search(query, entity_id)
    FolderIndex.filter(term: { entity_id: })
               .query(simple_query_string: { fields: FolderIndex::SEARCH_FIELDS,
                                             query:, default_operator: 'and' }).objects
  end

  scope :for_investor, lambda { |user, entity|
    joins(:access_rights)
      .merge(AccessRight.access_filter(user))
      .joins(entity: :investors)
      # Ensure that the user is an investor and tis investor has been given access rights
      .where("entities.id=?", entity.id)
      .where("investors.investor_entity_id=?", user.entity_id)
      # Ensure this user has investor access
      .joins(entity: :investor_accesses)
      .merge(InvestorAccess.approved_for_user(user))
  }

  def self.ransackable_attributes(_auth_object = nil)
    %w[full_path name owner_type].sort
  end

  private

  # Changed: Added resolve_effective_nda private method shared by effective_nda_config and nda_source_folder.
  # Why: Both methods need the same ancestry walk. Extracting avoids duplicating traversal logic.
  # @return [Array<(NdaConfig, Folder), (nil, nil)>]
  def resolve_effective_nda
    return [nda_config, self] if nda_own?
    return [nil, nil] if nda_opted_out?

    ancestors.reverse_each do |ancestor|
      return [ancestor.nda_config, ancestor] if ancestor.nda_own?
      return [nil, nil] if ancestor.nda_opted_out?
    end

    [nil, nil]
  end
end
