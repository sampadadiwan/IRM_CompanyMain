class AccountEntry < ApplicationRecord
  include WithCustomField
  include FundScopes

  belongs_to :capital_commitment, optional: true
  belongs_to :entity
  belongs_to :fund
  belongs_to :investor, optional: true
  belongs_to :parent, polymorphic: true, optional: true

  serialize :explanation, Array

  monetize :amount_cents, with_currency: ->(i) { i.fund.currency }

  validates :name, :reporting_date, :entry_type, presence: true
  validates :amount_cents,
            uniqueness: { scope: %i[fund_id capital_commitment_id name entry_type reporting_date cumulative],
                          message: "Duplicate Account Entry for reporting date" }

  scope :cumulative, -> { where(cumulative: true) }
  scope :not_cumulative, -> { where.not(cumulative: true) }

  counter_culture :capital_commitment,
                  column_name: proc { |r| !r.cumulative && r.entry_type == "Expense" ? 'total_allocated_expense_cents' : nil },
                  delta_column: 'amount_cents',
                  column_names: {
                    ["account_entries.entry_type = ? and cumulative = ?", "Expense", false] => 'total_allocated_expense_cents'
                  }

  counter_culture :capital_commitment,
                  column_name: proc { |r| !r.cumulative && r.entry_type == "Income" ? 'total_allocated_income_cents' : nil },
                  delta_column: 'amount_cents',
                  column_names: {
                    ["account_entries.entry_type = ? and cumulative = ?", "Income", false] => 'total_allocated_income_cents'
                  }

  before_validation :setup_period
  def setup_period
    self.period = "Q#{(reporting_date.month / 3.0).ceil}-#{reporting_date.year}" if period.blank?
  end

  def to_s
    "#{reporting_date} #{name}"
  end

  def self.total_amount(entry_type, cumulative: false, start_date: nil, end_date: nil)
    account_entries = AccountEntry.where(entry_type:, cumulative:)
    account_entries = account_entries.where(reporting_date: start_date..) if start_date
    account_entries = account_entries.where(reporting_date: ..end_date) if end_date
    account_entries.sum(:amount_cents)
  end
end
