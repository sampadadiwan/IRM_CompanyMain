class Approval < ApplicationRecord
  include WithFolder

  belongs_to :entity
  has_rich_text :agreements_reference
  has_many :access_rights, as: :owner, dependent: :destroy
  has_many :documents, as: :owner, dependent: :destroy
  has_many :approval_responses, dependent: :destroy

  def name
    title
  end

  def setup_folder_details
    parent_folder = Folder.where(entity_id:, level: 1, name: self.class.name.pluralize.titleize).first
    setup_folder(parent_folder, title, [])
  end
end
