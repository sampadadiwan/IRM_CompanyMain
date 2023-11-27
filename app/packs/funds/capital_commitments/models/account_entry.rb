class AccountEntry < ApplicationRecord
  include WithCustomField
  include WithExchangeRate
  include ForInvestor

  belongs_to :capital_commitment, optional: true
  belongs_to :entity
  belongs_to :fund
  belongs_to :investor, optional: true
  belongs_to :parent, polymorphic: true, optional: true

  enum :commitment_type, { Pool: "Pool", CoInvest: "CoInvest", All: "All" }
  scope :pool, -> { where(commitment_type: 'Pool') }
  scope :co_invest, -> { where(commitment_type: 'CoInvest') }

  # Used in has_scope of controller
  scope :reporting_date_start, ->(reporting_date_start) { where("reporting_date >= ?", reporting_date_start) }
  scope :reporting_date_end, ->(reporting_date_end) { where("reporting_date <= ?", reporting_date_end) }
  scope :entry_type, ->(entry_type) { where(entry_type:) }
  scope :folio_id, ->(folio_id) { where(folio_id:) }
  scope :unit_type, ->(unit_type) { where('capital_commitments.unit_type': unit_type) }
  scope :cumulative, -> { where(cumulative: true) }
  scope :not_cumulative, -> { where.not(cumulative: true) }

  serialize :explanation, type: Array

  monetize :folio_amount_cents, with_currency: ->(i) { i.capital_commitment&.folio_currency || i.fund.currency }
  monetize :amount_cents, with_currency: ->(i) { i.fund.currency }

  validates :name, :reporting_date, :entry_type, presence: true
  validates :name,
            uniqueness: { scope: %i[fund_id capital_commitment_id entry_type reporting_date cumulative],
                          message: "Duplicate Account Entry for reporting date" }

  # counter_culture :capital_commitment,
  #                 column_name: proc { |r| !r.cumulative && r.entry_type == "Expense" ? 'total_allocated_expense_cents' : nil },
  #                 delta_column: 'amount_cents',
  #                 column_names: {
  #                   ["account_entries.entry_type = ? and cumulative = ?", "Expense", false] => 'total_allocated_expense_cents'
  #                 }

  # counter_culture :capital_commitment,
  #                 column_name: proc { |r| !r.cumulative && r.entry_type == "Income" ? 'total_allocated_income_cents' : nil },
  #                 delta_column: 'amount_cents',
  #                 column_names: {
  #                   ["account_entries.entry_type = ? and cumulative = ?", "Income", false] => 'total_allocated_income_cents'
  #                 }

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

  def to_s
    "#{reporting_date} #{name}"
  end

  def self.total_amount(account_entries, entry_type, cumulative: false, start_date: nil, end_date: nil)
    account_entries = account_entries.where(entry_type:, cumulative:)
    account_entries = account_entries.where(reporting_date: start_date..) if start_date
    account_entries = account_entries.where(reporting_date: ..end_date) if end_date
    account_entries.sum(:amount_cents)
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[amount_cents commitment_type cumulative entry_type folio_id generated name period reporting_date]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[capital_commitment fund investor]
  end
end
