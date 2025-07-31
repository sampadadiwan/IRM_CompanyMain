class Investor < ApplicationRecord
  include WithCustomField
  include Trackable.new
  include UpdateInvestor
  include WithFolder
  include WithFriendlyId
  include WithIncomingEmail
  include Pundit::Authorization
  include WithDocQuestions
  include ForInvestor

  update_index('investor') { self if index_record? }

  # This is to be set if we want the investor name to be different from the investor_entity name
  attr_accessor :force_different_name

  # Any description of the investor
  has_rich_text :description

  belongs_to :investor_entity, class_name: "Entity"
  has_many :kpi_reports, through: :investor_entity
  # These are uploaded by the fund for its own portfolio_companies
  has_many :portfolio_kpi_reports, class_name: "KpiReport", foreign_key: :portfolio_company_id
  has_many :portfolio_kpis, class_name: "Kpi", through: :portfolio_kpi_reports, source: :kpis
  has_many :portfolio_report_extracts, dependent: :destroy, foreign_key: :portfolio_company_id

  belongs_to :entity, touch: true
  counter_culture :entity

  # The InvestorAccess attached to this investor
  has_many :investor_accesses, dependent: :destroy
  has_many :investor_advisors,
           through: :investor_entity,
           source: :investor_advisors

  has_many :investor_kpi_mappings, dependent: :destroy
  has_many :approved_investor_accesses, -> { where approved: true }, class_name: 'InvestorAccess'
  # The users linked to the InvestorAccess
  has_many :users, through: :investor_accesses
  has_many :approved_users, through: :approved_investor_accesses, source: :user
  has_many :rm_mappings, dependent: :destroy
  has_many :rm_mappings_as_rm, class_name: "RmMapping", foreign_key: :rm_id, dependent: :destroy
  has_many :mapped_investors_as_rm, through: :rm_mappings_as_rm, source: :investor

  has_many :tasks, as: :owner, dependent: :destroy
  has_many :valuations, as: :owner, dependent: :destroy

  # These are the access rights for the investor, to access items like Fund, InvestmentOpportunity, SecondarySale etc
  has_many :access_rights, foreign_key: :access_to_investor_id, dependent: :destroy
  # These are the access rights for employees, advisors etc, to access the details of this investor
  has_many :investor_access_rights, class_name: "AccessRight", as: :owner, dependent: :destroy

  has_many :deal_investors, dependent: :destroy
  has_many :deals, through: :deal_investors
  has_many :notes, dependent: :destroy
  has_many :aggregate_portfolio_investments, dependent: :destroy, foreign_key: :portfolio_company_id
  has_many :portfolio_investments, dependent: :destroy, foreign_key: :portfolio_company_id
  has_many :investment_instruments, dependent: :destroy, foreign_key: :portfolio_company_id
  has_many :portfolio_cashflows, dependent: :destroy, foreign_key: :portfolio_company_id
  has_many :stock_adjustments, dependent: :destroy, foreign_key: :portfolio_company_id

  has_many :investments, dependent: :destroy, foreign_key: :portfolio_company_id

  has_many :investor_kycs, dependent: :destroy
  has_many :capital_commitments, dependent: :destroy
  has_many :approval_responses, dependent: :destroy
  has_many :capital_distribution_payments, dependent: :destroy
  has_many :capital_remittances, dependent: :destroy
  has_many :fund_units, dependent: :destroy
  has_many :aml_reports, dependent: :destroy

  has_many :expression_of_interests, dependent: :destroy

  has_many :investor_notice_entries, dependent: :destroy

  has_many :offers, dependent: :destroy
  # has_many :messages, dependent: :destroy

  delegate :name, to: :entity, prefix: :investee
  validates :category, :investor_name, presence: true

  # Ensure investor_name is unique per entity_id
  validates :investor_name, uniqueness: { scope: :entity_id, message: "already exists as an investor. Duplicate Investor." }
  normalizes :investor_name, with: ->(investor_name) { investor_name.strip.squeeze(" ") }
  alias_attribute :name, :investor_name
  # Ensure unique investor_entity_id per entity_id
  validates :investor_entity_id, uniqueness: { scope: :entity_id, message: ": Investment firm already exists as an investor. Duplicate Investor." }

  validates :category, length: { maximum: 100 }
  validates :city, length: { maximum: 50 }
  validates :pan, length: { maximum: 40 }
  normalizes :pan, with: ->(pan) { pan.strip.squeeze(" ") }

  validates :primary_email, presence: true, if: proc { |e| e.new_record? }

  validates_uniqueness_of :pan, scope: :entity_id, allow_blank: true, allow_nil: true, message: "already exists as an investor. Duplicate Investor."
  validates_uniqueness_of :investor_name, scope: :entity_id, message: "already exists as an investor. Duplicate Investor."

  validates :tag_list, length: { maximum: 120 }

  scope :for_employee, lambda { |user|
    joins(:investor_access_rights).where(investor_access_rights: { user_id: user.id })
  }

  scope :for, lambda { |user, startup_entity|
                where(entity_id: startup_entity.id,
                      investor_entity_id: user.entity_id)
              }

  scope :advisors, -> { where(category: "Investor Advisor") }
  scope :rms, -> { where(category: ["RM", "Wealth Manager"]) }
  scope :portfolio_companies, -> { where(category: "Portfolio Company") }
  scope :not_portfolio_companies, -> { where.not(category: "Portfolio Company") }
  scope :not_advisors, -> { where.not(category: "Investor Advisor") }
  scope :not_rms, -> { where.not(category: "RM") }
  scope :without_investor_accesses, -> { where(investor_access_count: 0) }

  scope :for_vc, ->(vc_user) { where(investor_entity_id: vc_user.entity_id) }
  scope :not_interacted, ->(no_of_days) { where(last_interaction_date: ...(Time.zone.today - no_of_days.days)) }

  scope :with_access_rights, lambda { |entity_id, metadata|
    joins(entity: :access_rights).where(entity_id:).where("access_rights.access_to_category=investors.category or access_rights.access_to_investor_id=investors.id").where("access_rights.metadata=?", metadata)
  }

  scope :with_any_tags, lambda { |tags|
    next none if tags.blank?

    tag_list = tags.split(",").map(&:strip).compact_blank
    tag_list.inject(nil) do |scope, tag|
      condition = where("tag_list LIKE ?", "%#{tag}%")
      scope ? scope.or(condition) : condition
    end
  }

  # Get the investors associated with owner (Fund) which has access rights for investors
  scope :owner_access_rights, lambda { |owner, metadata|
    if metadata
      joins(entity: :access_rights).where(entity_id: owner.entity_id).where("access_rights.access_to_category=investors.category or access_rights.access_to_investor_id=investors.id").where("access_rights.metadata=?", metadata).where("owner_id=? and owner_type=?", owner.id, owner.class.name)
    else
      joins(entity: :access_rights).where(entity_id: owner.entity_id).where("access_rights.access_to_category=investors.category or access_rights.access_to_investor_id=investors.id").where("owner_id=? and owner_type=?", owner.id, owner.class.name)
    end
  }

  scope :perms, ->(p) { joins(:investor_entity).merge(Entity.perms(p)) }
  scope :no_perms, ->(p) { joins(:investor_entity).merge(Entity.no_perms(p)) }

  STANDARD_COLUMNS = { "Stakeholder" => "investor_name", "Tags" => "tag_list", "Category" => "category", "Access" => "investor_access_count" }.freeze
  INVESTOR_CATEGORIES = ENV["INVESTOR_CATEGORIES"].split(",") << "Prospective"

  def self.INVESTOR_CATEGORIES(entity = nil)
    cats = entity && entity.investor_categories.present? ? entity.investor_categories.split(",").map(&:strip) : INVESTOR_CATEGORIES
    cats += %w[Prospective]
    cats += ["Portfolio Company"] if ["Investment Fund", "Angel Fund"].include?(entity.entity_type) && entity
    cats
  end

  after_commit :change_investor_entity, if: :saved_change_to_investor_entity_id?

  after_create_commit -> { InvestorAddedJob.perform_later(id) unless imported }

  before_destroy :update_name_defunct
  def update_name_defunct
    update_column(:investor_name, "#{investor_name} Defunct #{rand(10_000)}")
  end

  before_validation :update_name, if: :new_record?

  def update_name
    self.last_interaction_date ||= Time.zone.today - 10.years

    # Ensure we have an investor entity
    e = primary_email ? Entity.where(primary_email: primary_email.strip).first : nil
    e ||= pan.present? ? Entity.where(pan: pan.strip).first : nil

    # We dont have this entity in our DB, lets create one.
    e ||= Entity.create(name: investor_name.strip, entity_type: "Investor", pan:, primary_email:)

    errors.add(:investor_name, "is not valid. #{e.errors.full_messages}") unless e.valid?
    setup_permissions(e)
    e.save

    self.investor_entity = e

    self.investor_name = investor_entity.name if investor_name.blank?
    self.pan ||= investor_entity.pan
  end

  def setup_permissions(investor_entity)
    # We need to enable features if the entity creating the investor has them turned on
    # Ex. an Investment Fund creates and investor, who should have funds enabled
    investor_entity.permissions.set(:enable_documents) if entity.permissions.enable_documents?
    investor_entity.permissions.set(:enable_investments) if entity.permissions.enable_investments?
    investor_entity.permissions.set(:enable_secondary_sale) if entity.permissions.enable_secondary_sale?
    investor_entity.permissions.set(:enable_captable) if entity.permissions.enable_captable?

    investor_entity.permissions.set(:enable_funds) if entity.permissions.enable_funds?
    investor_entity.permissions.set(:enable_units) if entity.permissions.enable_units?
    investor_entity.permissions.set(:enable_kpis) if entity.permissions.enable_kpis?
    investor_entity.permissions.set(:enable_kycs) if entity.permissions.enable_kycs?
    investor_entity.permissions.set(:enable_approvals) if entity.permissions.enable_approvals?
    investor_entity.permissions.set(:enable_inv_opportunities) if entity.permissions.enable_inv_opportunities?
  end

  def to_s
    "#{investor_name} : #{category}"
  end

  def for_friendly_id
    "#{investor_name}-#{id}"
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

  # Returns the aggregate portfolio investment for the given fund and as_of
  # Used in the FundFormulas to compute fund spcific AccountEntries
  def aggregate_portfolio_investment(fund_id: nil, as_of: nil)
    PortfolioCompanyCalc.new(self, fund_id:, as_of:).calculate
  end

  def folder_path
    "/Investors/#{investor_name.delete('/')}"
  end

  # callback but only for category = Portfolio Company
  def valuation_updated(valuation)
    # Ensure the portfolio_investments calculate the fmv
    pis = entity.portfolio_investments.where(portfolio_company_id: id,
                                             investment_instrument: valuation.investment_instrument)
    pis.each do |pi|
      PortfolioInvestmentUpdate.call(portfolio_investment: pi)
    end
  end

  def self.ransackable_associations(_auth_object = nil)
    []
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[pan city category investor_name tag_list investor_access_count unapproved_investor_access_count].sort
  end

  def update_investor_name(name)
    Rails.logger.debug { "Setting name for #{id} to #{name}" }
    update_column(:investor_name, name)
    reload
    CapitalCommitment.where(investor_id: id).update_all(investor_name:)
    CapitalRemittance.where(investor_id: id).update_all(investor_name:)
    CapitalDistributionPayment.where(investor_id: id).update_all(investor_name:)
    InvestorKyc.where(investor_id: id).update_all(investor_name:)
  end

  # We do this because of advisors
  # We dont want to send notifications to all approved users, we send it only if they have at least show access to the model
  def notification_users(model = nil)
    if model
      # Select all users who have show access to the model
      approved_users.select do |user|
        if user.has_cached_role?(:investor_advisor)
          # This is done because investor_advisors can switch entities and may be logged in as a different entity
          user.curr_role = "investor"
          Pundit.policy(user, model).permissioned_investor_advisor?(as_entity_id: investor_entity_id)
        else
          # For normal users, we check if they have show access to the model
          Pundit.policy(user, model).show?
        end
      end
    else
      approved_users
    end
  end

  def add_to_user_access_rights_cache(access_right)
    approved_users.each do |user|
      user.cache_access_rights(access_right, for_entity_id: investor_entity_id) # unless user.has_cached_role?(:investor_advisor)
    end
  end

  def remove_from_user_access_rights_cache(access_right)
    approved_users.each do |user|
      user.remove_access_rights_cache(access_right, for_entity_id: investor_entity_id) # unless user.has_cached_role?(:investor_advisor)
    end
  end

  def amount_invested
    amount = 0

    portfolio_investments.buys.each do |pi|
      Rails.logger.debug { "Calculating amount invested for #{pi.investment_instrument.name} on #{pi.investment_date} from #{pi.fund.currency} to #{entity.currency}" }

      bought_amount_cents = ExchangeRate.convert(pi.fund.currency, entity.currency, pi.amount_cents, pi.investment_date, entity_id, raise_missing_rate_error: true)
      amount += bought_amount_cents
    end

    Money.new(amount, entity.currency)
  end
end
