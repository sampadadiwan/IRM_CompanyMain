# == Schema Information
#
# Table name: entities
#
#  id                     :integer          not null, primary key
#  name                   :string(255)
#  url                    :string(255)
#  category               :string(255)
#  founded                :date
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  logo_url               :text(65535)
#  active                 :boolean          default("1")
#  entity_type            :string(15)
#  created_by             :integer
#  investor_categories    :string(255)
#  instrument_types       :string(255)
#  s3_bucket              :string(255)
#  deleted_at             :datetime
#  investors_count        :integer          default("0"), not null
#  investments_count      :integer          default("0"), not null
#  deals_count            :integer          default("0"), not null
#  deal_investors_count   :integer          default("0"), not null
#  documents_count        :integer          default("0"), not null
#  total_investments      :decimal(20, )    default("0")
#  is_holdings_entity     :boolean          default("0")
#  enable_documents       :boolean          default("0")
#  enable_deals           :boolean          default("0")
#  enable_investments     :boolean          default("0")
#  enable_holdings        :boolean          default("0")
#  enable_secondary_sale  :boolean          default("0")
#  parent_entity_id       :integer
#  currency               :string(10)
#  units                  :string(15)
#  trial_end_date         :date
#  trial                  :boolean          default("0")
#  tasks_count            :integer
#  pending_accesses_count :integer
#  active_deal_id         :integer
#  equity                 :integer          default("0")
#  preferred              :integer          default("0")
#  options                :integer          default("0")
#

class Entity < ApplicationRecord
  include Trackable

  # encrypts :name, deterministic: true
  validates :name, uniqueness: true
  # Make all models searchable
  update_index('entity') { self }

  validates :name, :entity_type, presence: true

  has_rich_text :details
  has_many :option_pools, dependent: :destroy
  has_many :deals, dependent: :destroy
  has_many :deal_investors, dependent: :destroy
  has_many :documents, dependent: :destroy
  has_many :secondary_sales, dependent: :destroy
  has_many :funding_rounds, dependent: :destroy
  has_many :valuations, dependent: :destroy

  # Will have many employees
  has_many :employees, class_name: "User", dependent: :destroy
  has_many :holdings, dependent: :destroy
  has_many :messages, dependent: :destroy

  # List of investors who are invested in this entity
  has_many :investors, dependent: :destroy
  has_many :investor_entities, through: :investors

  has_many :interests_shown, class_name: "Interest", foreign_key: "interest_entity_id", dependent: :destroy

  # List of investors where this entity is an investor
  has_many :investees, foreign_key: "investor_entity_id", class_name: "Investor", dependent: :destroy
  has_many :investee_entities, through: :investees
  has_many :notes, dependent: :destroy
  has_many :folders, dependent: :destroy

  has_many :investor_accesses, dependent: :destroy
  has_many :access_rights, dependent: :destroy
  has_many :investments, dependent: :destroy
  has_many :aggregate_investments, dependent: :destroy

  has_one_attached :logo, service: :amazon

  monetize :total_investments, as: "total", with_model_currency: :currency

  TYPES = ["VC", "Startup", "Holding", "Advisor", "Family Office"].freeze
  SECONDARY_BUYERS = ["VC", "Advisor", "Family Office"].freeze

  FUNDING_UNITS = %w[Lakhs Crores].freeze
  PLANS = ENV['PLANS'].split(",")

  scope :holdings, -> { where(entity_type: "Holding") }
  scope :vcs, -> { where(entity_type: "VC") }
  scope :startups, -> { where(entity_type: "Startup") }
  scope :advisors, -> { where(entity_type: "Advisor") }
  scope :user_investor_entities, ->(user) { where('access_rights.access_to': user.email).includes(:access_rights) }

  before_save :check_url, :scrub_defaults
  def check_url
    self.url = "http://#{url}" if url.present? &&
                                  !(url.starts_with?("http") || url.starts_with?("https"))
    self.logo_url = "http://#{logo_url}" if logo_url.present? &&
                                            !(logo_url.starts_with?("http") || logo_url.starts_with?("https"))
  end

  after_create ->(entity) { SetupStartup.call(entity:) if entity.entity_type == "Startup" }

  def to_s
    name
  end

  def scrub_defaults
    self.investor_categories = investor_categories.split(",").map(&:strip).join(",") if investor_categories
    self.instrument_types = instrument_types.split(",").map(&:strip).join(",") if instrument_types
    self.currency ||= "INR"
  end

  def self.for_investor(user)
    Entity.joins(:investor_accesses).where("investor_accesses.user_id=?", user.id).distinct
  end

  def trust_investor
    investors.is_trust.first
  end

  def recompute_investment_percentages(force: false)
    count = Entity.where(id:, percentage_in_progress: false).update_all(percentage_in_progress: true)
    InvestmentPercentageHoldingJob.set(wait: 1.minute).perform_later(id) if count.positive? || force
  rescue ActiveRecord::StaleObjectError => e
    Rails.logger.info "StaleObjectError: #{e.message}"
  end

  def self.recompute_all
    Entity.startups.each do |entity|
      entity.recompute_investment_percentages(force: true)
    end
    nil
  end
end
