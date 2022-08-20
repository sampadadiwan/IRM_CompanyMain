class Fund < ApplicationRecord
  include WithFolder

  belongs_to :entity
  has_many :documents, as: :owner, dependent: :destroy
  has_many :capital_commitments, dependent: :destroy
  has_many :capital_calls, dependent: :destroy
  has_many :access_rights, as: :owner, dependent: :destroy

  monetize :committed_amount_cents, :collected_amount_cents, with_currency: ->(i) { i.entity.currency }

  validates :name, presence: true

  def setup_folder_details
    parent_folder = Folder.where(entity_id:, level: 1, name: self.class.name.pluralize.titleize).first
    setup_folder(parent_folder, name, [])
  end
end
