class Folder < ApplicationRecord
  include Trackable
  has_ancestry orphan_strategy: :destroy, touch: true

  update_index('folder') { self }

  enum :folder_type, %i[regular system]

  belongs_to :parent, class_name: "Folder", optional: true
  belongs_to :entity, touch: true
  belongs_to :owner, polymorphic: true, optional: true

  has_many :documents, dependent: :destroy
  accepts_nested_attributes_for :documents, allow_destroy: true

  has_many :access_rights, as: :owner, dependent: :destroy

  validates :name, presence: true

  before_create :set_defaults
  after_create :set_parent_permissions, if: :parent
  # after_destroy :touch_root

  scope :for, ->(user) { where("folders.entity_id=?", user.entity_id).order("full_path asc") }
  scope :for_entity, ->(entity) { where("folders.entity_id=?", entity.id).order("full_path asc") }

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

  def set_parent_permissions
    parent.access_rights.each do |parent_ar|
      folder_ar = parent_ar.dup
      folder_ar.owner = self
      folder_ar.access_type = 'Folder'
      folder_ar.save
    end

    # If we have an owner for the parent and none for the child
    if parent.owner && owner.nil?
      self.owner = parent.owner
      save
    end
  end

  def touch_root
    Folder.where(entity_id:, level: 0).first.touch
  end

  # This is triggered when the access rights change
  def access_rights_changed(access_right)
    access_right = AccessRight.where(id: access_right.id).first
    FolderAccessJob.perform_later(id, access_right.id) if access_right&.cascade
  end

  def self.search(query, entity_id)
    FolderIndex.filter(term: { entity_id: })
               .query(query_string: { fields: FolderIndex::SEARCH_FIELDS,
                                      query:, default_operator: 'and' }).objects
  end

  def self.with_ancestor_ids(documents)
    ids = documents.joins(:folder).pluck("documents.folder_id, folders.ancestry")
    ids.map { |p| p[1] ? (p[1].split("/") << p[0]) : [p[0]] }.flatten.map(&:to_i)
  end
end
