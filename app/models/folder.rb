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

  belongs_to :parent, class_name: "Folder", foreign_key: :parent_folder_id, optional: true
  belongs_to :entity
  has_many :documents, dependent: :destroy
  has_many :access_rights, as: :owner, dependent: :destroy
  has_many_attached :docs, service: :amazon

  # Stores all the ids of folders till root from this Folder, i.e all ids from root till here
  serialize :path_ids

  validates :name, presence: true

  before_create :set_defaults
  after_create :touch_root
  before_destroy :destroy_child_folders
  after_destroy :touch_root

  scope :for, ->(user) { where("folders.entity_id=?", user.entity_id).order("full_path asc") }

  def set_defaults
    if parent
      self.level = parent.level + 1
      self.full_path = level == 1 ? "#{parent.full_path}#{name}" : "#{parent.full_path}/#{name}"
      self.path_ids = parent.path_ids + [parent.id]
    else
      self.level = 0
      self.full_path = "/"
      self.path_ids = []
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
end
