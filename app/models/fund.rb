class Fund < ApplicationRecord
  include WithFolder
  include ActivityTrackable
  tracked owner: proc { |_controller, model| model }, entity_id: proc { |_controller, model| model.entity_id }

  belongs_to :entity, touch: true
  belongs_to :funding_round
  has_many :documents, as: :owner, dependent: :destroy
  has_many :capital_remittances, dependent: :destroy
  has_many :capital_commitments, dependent: :destroy
  has_many :capital_calls, dependent: :destroy
  has_many :access_rights, as: :owner, dependent: :destroy

  belongs_to :form_type, optional: true
  serialize :properties, Hash

  monetize :call_amount_cents, :committed_amount_cents, :collected_amount_cents, :distribution_amount_cents, with_currency: ->(i) { i.entity.currency }

  validates :name, presence: true

  before_validation :setup_funding_round
  def setup_funding_round
    self.funding_round = FundingRound.new(name:, entity_id:, status: "Open", currency: entity.currency)
  end

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

  def to_s
    name
  end
end
