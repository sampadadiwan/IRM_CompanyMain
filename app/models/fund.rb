class Fund < ApplicationRecord
  include WithFolder

  belongs_to :entity, touch: true
  has_many :documents, as: :owner, dependent: :destroy
  has_many :capital_remittances, dependent: :destroy
  has_many :capital_commitments, dependent: :destroy
  has_many :capital_calls, dependent: :destroy
  has_many :access_rights, as: :owner, dependent: :destroy

  belongs_to :form_type, optional: true
  serialize :properties, Hash

  monetize :call_amount_cents, :committed_amount_cents, :collected_amount_cents, with_currency: ->(i) { i.entity.currency }

  validates :name, presence: true

  def setup_folder_details
    parent_folder = Folder.where(entity_id:, level: 1, name: self.class.name.pluralize.titleize).first
    setup_folder(parent_folder, name, ["Capital Calls"])
  end

  def investors
    investor_list = []
    access_rights.includes(:investor).find_each do |ar|
      investor_list += ar.investors
    end
    investor_list.uniq
  end

  def self.for_investor(user)
    Fund
      # Ensure the access rghts for Document
      .joins(:access_rights)
      .merge(AccessRight.access_filter)
      .joins(entity: :investors)
      # Ensure that the user is an investor and tis investor has been given access rights
      # .where("entities.id=?", entity.id)
      .where("investors.investor_entity_id=?", user.entity_id)
      # Ensure this user has investor access
      .joins(entity: :investor_accesses)
      .merge(InvestorAccess.approved_for_user(user))
  end
end
