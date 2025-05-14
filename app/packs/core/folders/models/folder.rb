class Folder < ApplicationRecord

  include Trackable.new
  has_ancestry orphan_strategy: :destroy, touch: true

  update_index('folder') { self if index_record? }

  enum :folder_type, %i[regular system]

  belongs_to :parent, class_name: "Folder", optional: true
  belongs_to :entity
  belongs_to :owner, polymorphic: true, optional: true

  has_many :documents, dependent: :destroy
  accepts_nested_attributes_for :documents, allow_destroy: true

  has_many :access_rights, as: :owner, dependent: :destroy

  validates :name, presence: true
  normalizes :name, with: ->(name) { name.strip }

  validates :full_path, uniqueness: { scope: %i[owner_id owner_type entity_id], message: "combination must be unique" }

  before_create :set_defaults
  after_create :set_parent_permissions, if: :parent

  scope :for, ->(user) { where("folders.entity_id=?", user.entity_id).order("full_path asc") }
  scope :for_entity, ->(entity) { where("folders.entity_id=?", entity.id).order("full_path asc") }
  scope :private_folders, -> { where("folders.private=?", true) }

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

  def set_parent_permissions
    parent.access_rights.each do |parent_ar|
      folder_ar = parent_ar.dup
      folder_ar.owner = self
      folder_ar.access_type = 'Folder'
      folder_ar.notify = false
      folder_ar.save
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
               .query(query_string: { fields: FolderIndex::SEARCH_FIELDS,
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
end
