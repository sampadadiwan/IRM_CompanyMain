# == Schema Information
#
# Table name: folders
#
#  id               :integer          not null, primary key
#  name             :string(255)
#  parent_folder_id :integer
#  full_path        :text(65535)
#  level            :integer
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  entity_id        :integer          not null
#  documents_count  :integer          default("0"), not null
#  path_ids         :string(255)
#

class Folder < ApplicationRecord
  include TreeBuilder
  update_index('folder') { self }

  enum :folder_type, %i[regular system]

  belongs_to :parent, class_name: "Folder", foreign_key: :parent_folder_id, optional: true
  has_many :folders, foreign_key: :parent_folder_id, dependent: :destroy
  belongs_to :entity
  belongs_to :owner, polymorphic: true, optional: true

  has_many :documents, dependent: :destroy
  accepts_nested_attributes_for :documents, allow_destroy: true

  has_many :access_rights, as: :owner, dependent: :destroy

  # Stores all the ids of folders till root from this Folder, i.e all ids from root till here
  serialize :path_ids

  validates :name, presence: true

  before_create :set_defaults
  after_create :touch_root
  before_destroy :destroy_child_folders
  after_destroy :touch_root

  scope :for, ->(user) { where("folders.entity_id=?", user.entity_id).order("full_path asc") }
  scope :for_entity, ->(entity) { where("folders.entity_id=?", entity.id).order("full_path asc") }

  def set_defaults
    if parent
      self.level = parent.level + 1
      self.full_path = level == 1 ? "#{parent.full_path}#{name}" : "#{parent.full_path}/#{name}"
      self.path_ids = parent.path_ids + [parent.id]
      self.folder_type ||= :regular
    else
      self.level = 0
      self.full_path = "/"
      self.path_ids = []
      self.folder_type = :system
    end
  end

  def destroy_child_folders
    Folder.where(parent_folder_id: id).find_each do |f|
      f.destroy if f.level != 0
    end
  end

  def touch_root
    Folder.where(entity_id:, level: 0).first.touch
  end

  # This is triggered when the access rights change
  def access_rights_changed(access_right_id)
    FolderAccessJob.perform_later(id, access_right_id)
  end

  def self.search(query, entity_id)
    FolderIndex.filter(term: { entity_id: })
               .query(query_string: { fields: FolderIndex::SEARCH_FIELDS,
                                      query:, default_operator: 'and' }).objects
  end
end
