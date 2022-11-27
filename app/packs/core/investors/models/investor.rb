class Investor < ApplicationRecord
  # include Trackable
  include WithFolder
  update_index('investor') { self }

  # encrypts :investor_name, deterministic: true

  acts_as_taggable_on :tags

  belongs_to :investor_entity, class_name: "Entity"
  belongs_to :entity, touch: true
  counter_culture :entity

  # The InvestorAccess attached to this investor
  has_many :investor_accesses, dependent: :destroy
  has_many :approved_investor_accesses, -> { where approved: true }, class_name: 'InvestorAccess'
  # The users linked to the InvestorAccess
  has_many :users, through: :investor_accesses
  has_many :approved_users, through: :approved_investor_accesses, source: :user

  has_many :tasks, as: :owner, dependent: :destroy

  has_many :access_rights, foreign_key: :access_to_investor_id, dependent: :destroy
  has_many :deal_investors, dependent: :destroy
  has_many :deals, through: :deal_investors
  has_many :holdings, dependent: :destroy
  has_many :notes, dependent: :destroy

  has_many :documents, as: :owner, dependent: :destroy
  accepts_nested_attributes_for :documents, allow_destroy: true

  has_many :investor_kycs, dependent: :destroy
  has_many :capital_commitments, dependent: :destroy
  has_many :approval_responses, dependent: :destroy
  has_many :capital_distribution_payments, dependent: :destroy
  has_many :capital_remittances, dependent: :destroy

  has_many :investments, dependent: :destroy
  has_many :aggregate_investments, dependent: :destroy
  has_many :investor_notice_entries, dependent: :destroy

  # Customize form
  belongs_to :form_type, optional: true
  serialize :properties, Hash

  delegate :name, to: :entity, prefix: :investee
  validates :category, presence: true

  validates :investor_name, uniqueness: { scope: :entity_id, message: "already exists as an investor. Duplicate Investor." }
  validates :investor_entity_id, uniqueness: { scope: :entity_id, message: ": Investment firm already exists as an investor. Duplicate Investor." }

  scope :for, lambda { |user, startup_entity|
                where(entity_id: startup_entity.id,
                      investor_entity_id: user.entity_id)
              }

  scope :for_vc, ->(vc_user) { where(investor_entity_id: vc_user.entity_id) }
  scope :not_holding, -> { where(is_holdings_entity: false) }
  scope :not_trust, -> { where(is_trust: false) }
  scope :is_trust, -> { where(is_trust: true) }
  scope :holding, -> { where(is_holdings_entity: true) }
  scope :not_interacted, ->(no_of_days) { where(is_holdings_entity: false).where("last_interaction_date < ? ", Time.zone.today - no_of_days.days) }

  scope :with_access_rights, lambda { |entity_id, metadata|
    joins(entity: :access_rights).where(entity_id:).where("access_rights.access_to_category=investors.category or access_rights.access_to_investor_id=investors.id").where("access_rights.metadata=?", metadata)
  }

  scope :owner_access_rights, lambda { |owner, metadata|
    joins(entity: :access_rights).where(entity_id: owner.entity_id).where("access_rights.access_to_category=investors.category or access_rights.access_to_investor_id=investors.id").where("access_rights.metadata=?", metadata).where("owner_id=? and owner_type=?", owner.id, owner.class.name)
  }

  INVESTOR_CATEGORIES = ENV["INVESTOR_CATEGORIES"].split(",") << "Prospective"

  def self.INVESTOR_CATEGORIES(entity = nil)
    Investment.INVESTOR_CATEGORIES(entity) + %w[Prospective Advisor]
  end

  after_create -> { InvestorAddedJob.perform_later(id) }

  before_validation :update_name
  def update_name
    self.investor_name = investor_entity.name if investor_name.blank?
    self.last_interaction_date ||= Time.zone.today - 10.years

    # Ensure we have an investor entity
    if investor_entity_id.blank?
      e = Entity.where(name: investor_name).first
      unless e
        entity_type = category == "Advisor" ? "Advisor" : "VC"
        e = Entity.create(name: investor_name, entity_type:)
      end

      setup_permissions(e)
      e.save

      self.investor_entity = e
    end
  end

  def setup_permissions(investor_entity)
    # We need to enable features if the entity creating the investor has them turned on
    # Ex. an Investment Fund creates and investor, who should have funds enabled
    investor_entity.enable_documents = entity.enable_documents if entity.enable_documents
    investor_entity.enable_investments = entity.enable_investments if entity.enable_investments
    investor_entity.enable_holdings = entity.enable_holdings if entity.enable_holdings
    investor_entity.enable_secondary_sale = entity.enable_secondary_sale if entity.enable_secondary_sale
    investor_entity.enable_options = entity.enable_options if entity.enable_options
    investor_entity.enable_captable = entity.enable_captable if entity.enable_captable

    investor_entity.enable_funds = entity.enable_funds if entity.enable_funds
    investor_entity.enable_inv_opportunities = entity.enable_inv_opportunities if entity.enable_inv_opportunities
  end

  def to_s
    "#{investor_name} : #{category}"
  end

  def emails
    investor_accesses.approved.collect(&:email)
  end

  def folder_path
    "/Investors/#{investor_name}-#{id}"
  end

  def setup_folder_details
    setup_folder_from_path(folder_path)
  end
end
