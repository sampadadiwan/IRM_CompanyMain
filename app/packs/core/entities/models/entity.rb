class Entity < ApplicationRecord
  include Trackable
  include EntityMerge
  # encrypts :name, deterministic: true
  validates :name, uniqueness: true
  # Make all models searchable
  update_index('entity') { self }

  validates :name, :entity_type, presence: true

  has_rich_text :details
  belongs_to :parent_entity, class_name: "Entity", optional: true

  has_one :entity_setting, dependent: :destroy
  accepts_nested_attributes_for :entity_setting, allow_destroy: true

  has_many :option_pools, dependent: :destroy
  has_many :excercises, dependent: :destroy
  has_many :deals, dependent: :destroy
  has_many :deal_investors, dependent: :destroy
  has_many :deal_activities, dependent: :destroy

  has_many :secondary_sales, dependent: :destroy
  has_many :interests_shown, class_name: "Interest", foreign_key: "interest_entity_id", dependent: :destroy
  has_many :offers, dependent: :destroy

  has_many :funding_rounds, dependent: :destroy
  has_many :valuations, dependent: :destroy
  has_many :investor_notices, dependent: :destroy
  has_many :esigns, dependent: :destroy

  # Will have many employees
  has_many :employees, class_name: "User", dependent: :destroy
  has_many :documents, dependent: :destroy
  has_many :holdings, dependent: :destroy
  has_many :messages, dependent: :destroy
  has_many :tasks, dependent: :destroy
  has_many :approvals, dependent: :destroy
  has_many :approval_responses, dependent: :destroy

  # List of investors who are invested in this entity
  has_many :investors, dependent: :destroy
  has_many :investor_advisors, dependent: :destroy
  has_many :investor_entities, through: :investors
  # List of investor records in which this company is an investee

  # List of investors where this entity is an investor
  has_many :investees, foreign_key: "investor_entity_id", class_name: "Investor", dependent: :destroy
  has_many :investee_entities, through: :investees
  has_many :notes, dependent: :destroy
  has_many :folders, dependent: :destroy
  has_many :exchange_rates, dependent: :destroy
  has_many :fees, dependent: :destroy
  has_many :import_uploads, dependent: :destroy

  has_many :investor_accesses, dependent: :destroy
  has_many :investor_kycs, dependent: :destroy
  has_many :access_rights, dependent: :destroy
  has_many :investments, dependent: :destroy
  has_many :aggregate_investments, dependent: :destroy

  has_many :funds, dependent: :destroy, inverse_of: :entity
  has_many :capital_calls, dependent: :destroy
  has_many :capital_commitments, dependent: :destroy
  has_many :capital_remittances, dependent: :destroy
  has_many :capital_remittance_payments, dependent: :destroy
  has_many :capital_distributions, dependent: :destroy
  has_many :capital_distribution_payments, dependent: :destroy
  has_many :commitment_adjustments, dependent: :destroy
  has_many :fund_ratios, dependent: :destroy
  has_many :fund_units, dependent: :destroy
  has_many :fund_reports, dependent: :destroy
  has_many :fund_formulas, dependent: :destroy

  has_many :investment_opportunities, dependent: :destroy
  has_many :expression_of_interests, dependent: :destroy
  has_many :portfolio_investments
  has_many :aggregate_portfolio_investments

  include FileUploader::Attachment(:logo)

  monetize :total_investments, as: "total", with_model_currency: :currency
  monetize :per_share_value_cents, with_model_currency: :currency

  TYPES = ["Investor", "Investor Advisor", "Company", "Holding", "Investment Advisor", "Family Office", "Investment Fund", "Consulting"].freeze
  SECONDARY_BUYERS = ["Investor", "Investment Advisor", "Family Office"].freeze

  FUNDING_UNITS = %w[Lakhs Crores].freeze
  PLANS = ENV['PLANS'].split(",")

  scope :holdings, -> { where(entity_type: "Holding") }
  scope :vcs, -> { where(entity_type: "Investor") }
  scope :consulting, -> { where(entity_type: "Consulting") }
  scope :startups, -> { where(entity_type: "Company") }
  scope :investment_advisors, -> { where(entity_type: "Investment Advisor") }
  scope :investor_advisors, -> { where(entity_type: "Investor Advisor") }
  scope :family_offices, -> { where(entity_type: "Family Office") }
  scope :funds, -> { where(entity_type: "Investment Fund") }
  scope :user_investor_entities, ->(user) { where('access_rights.access_to': user.email).includes(:access_rights) }

  before_save :check_url, :scrub_defaults
  def check_url
    self.url = "http://#{url}" if url.present? &&
                                  !(url.starts_with?("http") || url.starts_with?("https"))
    self.logo_url = "http://#{logo_url}" if logo_url.present? &&
                                            !(logo_url.starts_with?("http") || logo_url.starts_with?("https"))
  end

  after_create_commit lambda { |_entity|
    # EntityMailer.with(id:).notify_created.deliver_later if id.present?
  }

  after_save :run_post_process, if: :saved_change_to_entity_type?
  def run_post_process
    case entity_type
    when "Company"
      SetupStartup.call(entity: self)
    else
      SetupFolders.call(entity: self)
    end

    # Ensure users entity_type is saved
    employees.each do |user|
      user.entity_type = entity_type
      user.save
    end
  end

  def to_s
    name
  end

  def scrub_defaults
    self.investor_categories = investor_categories.split(",").map(&:strip).join(",") if investor_categories
    self.instrument_types = instrument_types.split(",").map(&:strip).join(",") if instrument_types
    self.currency ||= "INR"
    self.entity_setting ||= EntitySetting.new
  end

  scope :for_investor, lambda { |user|
    joins(:investor_accesses).where("investor_accesses.user_id=?", user.id).distinct
  }

  def trust_investor
    investors.is_trust.first
  end

  def recompute_investment_percentages(force: false)
    count = Entity.where(id:, percentage_in_progress: false).update_all(percentage_in_progress: true)
    if count.positive? || force
      if Rails.env.test?
        InvestmentPercentageHoldingJob.perform_later(id)
      else
        InvestmentPercentageHoldingJob.set(wait: 1.minute).perform_later(id)
      end
    end
  rescue ActiveRecord::StaleObjectError => e
    Rails.logger.info "StaleObjectError: #{e.message}"
  end

  def self.recompute_all
    Entity.startups.each do |entity|
      entity.recompute_investment_percentages(force: true)
    end
    nil
  end

  def root_folder
    folders.where(level: 0).first
  end

  def advisor?(user)
    investors.where("investors.category=? and investors.investor_entity_id=?", 'Advisor', user.entity_id).first.present?
  end

  scope :advisor_for, lambda { |user|
    joins(:investors).where("investors.investor_entity_id=? and investors.category=?", user.entity_id, "Advisor")
  }

  def active_secondary_sale
    secondary_sales.where("secondary_sales.start_date <= ? and secondary_sales.end_date >= ?",
                          Time.zone.today, Time.zone.today).last
  end
end
