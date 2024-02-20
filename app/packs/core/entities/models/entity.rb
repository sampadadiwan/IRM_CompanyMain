class Entity < ApplicationRecord
  include Trackable.new
  # include EntityMerge
  # include InvestorEntityMerge
  include EntityEnabled

  # Make all models searchable
  update_index('entity') { self if index_record? }

  validates :name, :entity_type, presence: true
  validates_uniqueness_of :sub_domain, scope: :parent_entity_id, allow_blank: true, allow_nil: true
  validates_uniqueness_of :pan, allow_blank: true, allow_nil: true

  has_many :custom_notifications, as: :owner, dependent: :destroy

  validates :primary_email, presence: true, if: proc { |e| e.new_record? && !e.is_holdings_entity }

  validates_uniqueness_of :name, scope: :pan

  validates :name, length: { maximum: 255 }
  normalizes :name, with: ->(name) { name.strip.squeeze(" ") }

  validates :entity_type, length: { maximum: 25 }
  validates :currency, length: { maximum: 10 }
  validates :pan, length: { maximum: 40 }
  normalizes :pan, with: ->(pan) { pan.strip.squeeze(" ") }

  has_rich_text :details
  belongs_to :parent_entity, class_name: "Entity", optional: true
  has_many :children, class_name: "Entity", foreign_key: "parent_entity_id", dependent: :destroy

  has_one :entity_setting, dependent: :destroy
  accepts_nested_attributes_for :entity_setting, allow_destroy: true

  has_many :kpi_reports, dependent: :destroy
  has_many :kpis, dependent: :destroy
  has_many :investor_kpi_mappings, dependent: :destroy

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
  # has_many :esigns, dependent: :destroy

  # Will have many employees

  has_many :documents, dependent: :destroy
  has_many :holdings, dependent: :destroy
  has_many :messages, dependent: :destroy
  has_many :tasks, dependent: :destroy
  has_many :form_types, dependent: :destroy
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
  has_many :account_entries, dependent: :destroy
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
  has_many :investment_instruments
  has_many :aggregate_portfolio_investments

  # Noticed gem
  has_many :notifications, as: :recipient, dependent: :destroy
  has_many :employees, class_name: "User", dependent: :destroy

  include FileUploader::Attachment(:logo)

  monetize :total_investments, as: "total", with_model_currency: :currency
  monetize :per_share_value_cents, with_model_currency: :currency

  TYPES = ["Investor", "Investor Advisor", "Company", "Holding", "Investment Advisor", "Family Office", "Investment Fund", "Angel Fund", "Group Company"].freeze
  SECONDARY_BUYERS = ["Investor", "Investment Advisor", "Family Office"].freeze

  FUNDING_UNITS = %w[Lakhs Crores].freeze
  PLANS = ENV['PLANS'].split(",")

  default_scope { order(name: :asc) }
  scope :holdings, -> { where(entity_type: "Holding") }
  scope :vcs, -> { where(entity_type: "Investor") }
  scope :startups, -> { where(entity_type: "Company") }
  scope :investment_advisors, -> { where(entity_type: "Investment Advisor") }
  scope :investor_advisors, -> { where(entity_type: "Investor Advisor") }
  scope :family_offices, -> { where(entity_type: "Family Office") }
  scope :funds, -> { where(entity_type: "Investment Fund") }
  scope :user_investor_entities, ->(user) { where('access_rights.access_to': user.email).includes(:access_rights) }

  scope :perms, ->(p) { where_permissions(p.to_sym) }
  scope :no_perms, ->(p) { where_not_permissions(p.to_sym) }

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
    self.sub_domain ||= name.gsub(/[[:space:]]/, '').underscore.dasherize + rand(1000).to_s
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

  def update_passwords_to_pan(investor_list = nil)
    no_pans = []
    Rails.logger.debug { "Updating passwords for #{name}" }

    investor_list ||= investors

    investor_list.each do |investor|
      investor.investor_entity.employees.each do |u|
        if investor.pan
          if u.sign_in_count.positive?
            Rails.logger.debug { "Not updating password for #{u.email} as they have already logged in" }
          else
            Rails.logger.debug { "Updating password for #{u.email}" }
            u.password = investor.pan.downcase
            u.save
          end
        else
          Rails.logger.debug { "No PAN for #{investor.investor_name}" }
          no_pans << investor_entity.id
        end
      end
    end

    no_pans
  end

  def custom_notification(for_type = nil)
    custom_notifications.where(for: for_type).first
  end

  def is_fund?
    ["Investment Fund", "Angel Fund"].include?(entity_type)
  end

  def is_group_company?
    ["Group Company"].include?(entity_type)
  end

  def is_investor?
    ["Investor"].include?(entity_type)
  end

  def is_investment_advisor?
    ["Investment Advisor"].include?(entity_type)
  end

  def is_company?
    ["Company"].include?(entity_type)
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[category name]
  end
end
