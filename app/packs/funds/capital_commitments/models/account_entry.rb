class AccountEntry < ApplicationRecord
  # update_index('account_entry') { self if index_record? }

  include WithCustomField
  include WithExchangeRate
  include ForInvestor
  include Trackable.new(on: [:update])
  include RansackerAmounts.new(fields: %w[amount])

  STANDARD_COLUMN_NAMES = ["Fund", "Investor", "Folio", "Reporting Date", "Period", "Entry Type", "Name", "Amount",
                           "Type", " "].freeze
  STANDARD_COLUMN_FIELDS = %w[fund_name investor_name folio_id reporting_date period entry_type name amount commitment_type dt_actions].freeze

  INVESTOR_COLUMN_NAMES = ["Fund", "Investor", "Folio", "Reporting Date", "Period", "Entry Type", "Name", "Amount",
                           "Type", " "].freeze
  INVESTOR_COLUMN_FIELDS = %w[fund_name investor_name folio_id reporting_date period entry_type name amount commitment_type dt_actions].freeze

  belongs_to :capital_commitment, optional: true
  belongs_to :entity
  belongs_to :fund
  belongs_to :fund_formula, optional: true
  belongs_to :investor, optional: true
  belongs_to :parent, polymorphic: true, optional: true

  # Account entries come in 2 flavours, they are either accounting entries or reporting entries.
  enum :rule_for, { accounting: "Accounting", reporting: "Reporting" }

  enum :commitment_type, { Pool: "Pool", CoInvest: "CoInvest", All: "All" }
  scope :pool, -> { where(commitment_type: 'Pool') }
  scope :co_invest, -> { where(commitment_type: 'CoInvest') }

  # Used in has_scope of controller
  scope :reporting_date_start, ->(reporting_date_start) { where(reporting_date: reporting_date_start..) }
  scope :reporting_date_end, ->(reporting_date_end) { where(reporting_date: ..reporting_date_end) }
  scope :entry_type, ->(entry_type) { where(entry_type:) }
  scope :folio_id, ->(folio_id) { where(folio_id:) }
  scope :unit_type, ->(unit_type) { where('capital_commitments.unit_type': unit_type) }
  scope :cumulative, -> { where(cumulative: true) }
  scope :not_cumulative, -> { where.not(cumulative: true) }
  scope :generated, -> { where(generated: true) }

  serialize :explanation, type: Array

  monetize :folio_amount_cents, with_currency: ->(i) { i.capital_commitment&.folio_currency || i.fund.currency }
  monetize :amount_cents, with_currency: ->(i) { i.fund.currency }

  validates :name, :reporting_date, :entry_type, presence: true
  validates :name, length: { maximum: 125 }
  validates :name,
            uniqueness: { scope: %i[fund_id capital_commitment_id entry_type reporting_date cumulative deleted_at],
                          message: "Duplicate Account Entry for reporting date" }

  before_validation :setup_period
  def setup_period
    self.period = "Q#{(reporting_date.month / 3.0).ceil}-#{reporting_date.year}"
  end

  before_save :set_folio_amount, if: :capital_commitment
  def set_folio_amount
    # Since the account entry amount is always in the fund currency, we compute the converted folio_amount based on exchange rates.
    self.folio_amount_cents = convert_currency(fund.currency, capital_commitment.folio_currency,
                                               amount_cents, reporting_date)
  end

  before_save :setup_rule_for
  def setup_rule_for
    self.rule_for = if fund_formula.present? && fund_formula.reporting?
                        'reporting'
                      else
                        'accounting'
                      end
  end

  def to_s
    "#{reporting_date} #{name}"
  end

  def self.total_amount(account_entries, name: nil, entry_type: nil, cumulative: false, start_date: nil, end_date: nil)
    account_entries = account_entries.where(entry_type:) if entry_type
    account_entries = account_entries.where(name:) if name
    account_entries = account_entries.where(cumulative:)
    account_entries = account_entries.where(reporting_date: start_date..) if start_date
    account_entries = account_entries.where(reporting_date: ..end_date) if end_date
    account_entries.sum(:amount_cents)
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[capital_commitment_id amount commitment_type cumulative entry_type folio_id generated name period reporting_date].sort
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[capital_commitment fund investor]
  end

  def template_field_name
    name.titleize.delete(' :,;').underscore
  end

  def index_reporting_date
    entries_to_index = fund.account_entries.includes(:fund, :entity).where(reporting_date:)
    Rails.logger.debug { "Indexing #{entries_to_index.count} account entries for reporting date #{reporting_date}" }
    entries_to_index.each(&:run_chewy_callbacks)
    Rails.logger.debug { "Indexing completed. #{entries_to_index.count} account entries indexed for reporting date #{reporting_date}" }
  end
end
