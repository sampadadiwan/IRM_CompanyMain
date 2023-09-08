class Investor < ApplicationRecord
  include WithCustomField
  include Trackable
  include WithFolder
  include UpdateInvestor

  update_index('investor') { self }

  # This is to be set if we want the investor name to be different from the investor_entity name
  attr_accessor :force_different_name

  belongs_to :investor_entity, class_name: "Entity"
  has_many :kpi_reports, through: :investor_entity

  belongs_to :entity, touch: true
  counter_culture :entity

  # The InvestorAccess attached to this investor
  has_many :investor_accesses, dependent: :destroy
  has_many :approved_investor_accesses, -> { where approved: true }, class_name: 'InvestorAccess'
  # The users linked to the InvestorAccess
  has_many :users, through: :investor_accesses
  has_many :approved_users, through: :approved_investor_accesses, source: :user

  has_many :tasks, as: :owner, dependent: :destroy
  has_many :valuations, as: :owner, dependent: :destroy

  has_many :access_rights, foreign_key: :access_to_investor_id, dependent: :destroy
  has_many :deal_investors, dependent: :destroy
  has_many :deals, through: :deal_investors
  has_many :holdings, dependent: :destroy
  has_many :notes, dependent: :destroy
  has_many :aggregate_portfolio_investments, dependent: :destroy, foreign_key: :portfolio_company_id
  has_many :portfolio_investments, dependent: :destroy, foreign_key: :portfolio_company_id
  has_many :portfolio_cashflows, dependent: :destroy, foreign_key: :portfolio_company_id

  has_many :investor_kycs, dependent: :destroy
  has_many :capital_commitments, dependent: :destroy
  has_many :approval_responses, dependent: :destroy
  has_many :capital_distribution_payments, dependent: :destroy
  has_many :capital_remittances, dependent: :destroy
  has_many :fund_units, dependent: :destroy
  has_many :aml_reports, dependent: :destroy

  has_many :expression_of_interests, dependent: :destroy

  has_many :investments, dependent: :destroy
  has_many :aggregate_investments, dependent: :destroy
  has_many :investor_notice_entries, dependent: :destroy

  has_many :offers, dependent: :destroy
  has_many :messages, dependent: :destroy

  delegate :name, to: :entity, prefix: :investee
  validates :category, :investor_name, presence: true

  validates :investor_name, uniqueness: { scope: :entity_id, message: "already exists as an investor. Duplicate Investor." }
  validates :investor_entity_id, uniqueness: { scope: :entity_id, message: ": Investment firm already exists as an investor. Duplicate Investor." }
  validates :category, length: { maximum: 100 }
  validates :city, length: { maximum: 50 }
  validates :pan, length: { maximum: 15 }
  # We did not have PAN as mandatory before. But we need to make it mandatory, without forcing update to existing data. Hence this check for data created after PAN_MANDATORY_AFTER date
  validates :pan, presence: true, if: proc { |e| (e.created_at && e.created_at >= Entity::PAN_MANDATORY_AFTER) || ((e.new_record? && Time.zone.today >= Entity::PAN_MANDATORY_AFTER) && !e.is_holdings_entity && !e.is_trust) }

  validates_uniqueness_of :pan, scope: :entity_id, allow_blank: true, allow_nil: true, message: "already exists as an investor. Duplicate Investor."

  validates :tag_list, length: { maximum: 120 }

  scope :for, lambda { |user, startup_entity|
                where(entity_id: startup_entity.id,
                      investor_entity_id: user.entity_id)
              }

  scope :advisors, -> { where(category: "Investor Advisor") }
  scope :portfolio_companies, -> { where(category: "Portfolio Company") }
  scope :not_advisors, -> { where.not(category: "Investor Advisor") }

  scope :for_vc, ->(vc_user) { where(investor_entity_id: vc_user.entity_id) }
  scope :not_holding, -> { where(is_holdings_entity: false) }
  scope :not_trust, -> { where(is_trust: false) }
  scope :is_trust, -> { where(is_trust: true) }
  scope :holding, -> { where(is_holdings_entity: true) }
  scope :not_interacted, ->(no_of_days) { where(is_holdings_entity: false).where("last_interaction_date < ? ", Time.zone.today - no_of_days.days) }

  scope :with_access_rights, lambda { |entity_id, metadata|
    joins(entity: :access_rights).where(entity_id:).where("access_rights.access_to_category=investors.category or access_rights.access_to_investor_id=investors.id").where("access_rights.metadata=?", metadata)
  }

  # Get the investors associated with owner (Fund) which has access rights for investors
  scope :owner_access_rights, lambda { |owner, metadata|
    if metadata
      joins(entity: :access_rights).where(entity_id: owner.entity_id).where("access_rights.access_to_category=investors.category or access_rights.access_to_investor_id=investors.id").where("access_rights.metadata=?", metadata).where("owner_id=? and owner_type=?", owner.id, owner.class.name)
    else
      joins(entity: :access_rights).where(entity_id: owner.entity_id).where("access_rights.access_to_category=investors.category or access_rights.access_to_investor_id=investors.id").where("owner_id=? and owner_type=?", owner.id, owner.class.name)
    end
  }

  INVESTOR_CATEGORIES = ENV["INVESTOR_CATEGORIES"].split(",") << "Prospective"

  def self.INVESTOR_CATEGORIES(entity = nil)
    cats = Investment.INVESTOR_CATEGORIES(entity) + %w[Prospective]
    cats += ["Portfolio Company"] if entity.entity_type == "Investment Fund"
    cats
  end

  after_create_commit -> { InvestorAddedJob.perform_later(id) unless imported }

  before_validation :update_name, if: :new_record?

  def update_name
    self.last_interaction_date ||= Time.zone.today - 10.years

    # Ensure we have an investor entity
    if investor_entity_id.blank?
      e = pan ? Entity.where(pan: pan.strip).first : nil

      # If we do have an investor entity, and the name is not the same
      errors.add(:investor_name, "Investor name in our records for PAN #{pan} is #{e.name}.") if e && e.name.strip != investor_name.strip && !force_different_name

      # We dont have this entity in our DB, lets create one.
      e ||= Entity.create(name: investor_name.strip, entity_type: "Investor", pan:)

      setup_permissions(e)
      e.save

      self.investor_entity = e
    end

    self.investor_name = investor_entity.name if investor_name.blank?
    self.pan ||= investor_entity.pan
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
    investor_entity.enable_kpis = entity.enable_kpis if entity.enable_kpis
    investor_entity.enable_kycs = entity.enable_kpis if entity.enable_kycs
    investor_entity.enable_approvals = entity.enable_kpis if entity.enable_approvals
    investor_entity.enable_inv_opportunities = entity.enable_inv_opportunities if entity.enable_inv_opportunities
  end

  def to_s
    "#{investor_name} : #{category}"
  end

  def emails(type = "Employees")
    case type
    when "Employees"
      investor_accesses.approved.not_investor_advisors.pluck(:email)
    when "Investor Advisors"
      investor_accesses.approved.investor_advisors.pluck(:email)
    when "All"
      investor_accesses.approved.pluck(:email)
    end
  end

  def emails_for(model)
    employee_emails = emails("Employees")
    advisor_emails = investor_advisor_emails(model)
    employee_emails + advisor_emails
  end

  def investor_advisor_emails(model)
    access_user_ids = get_access_rights(model).pluck(:user_id)
    investor_accesses.approved.investor_advisors.where(user_id: access_user_ids).pluck(:email)
  end

  def get_access_rights(model)
    model.access_rights.where.not(user_id: nil).where(entity_id: investor_entity_id)
  end

  def investor_advisors(model)
    access_user_ids = get_access_rights(model).pluck(:user_id)
    User.where(id: investor_accesses.approved.investor_advisors.where(user_id: access_user_ids).pluck(:user_id), whatsapp_enabled: true)
  end

  def folder_path
    "/Investors/#{investor_name.delete('/')}"
  end

  # callback but only for category = Portfolio Company
  def valuation_updated(valuation)
    # Ensure the portfolio_investments calculate the fmv
    entity.portfolio_investments.where(portfolio_company_id: id,
                                       category: valuation.category, sub_category: valuation.sub_category).each(&:save)
  end

  def update_passwords
    investor_entity.employees.each do |u|
      u.password = self.pan
      u.save
    end
  end
end
