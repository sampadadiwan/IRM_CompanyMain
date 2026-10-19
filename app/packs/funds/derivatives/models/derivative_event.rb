# One event on a derivative contract. amount_cents is cash (+ received / − paid); value_cents is a
# valuation (contract currency, signed). idempotency_key makes a repeated submission harmless (E51).
# openspec/changes/fund-market-data — design card ⑥.
class DerivativeEvent < ApplicationRecord
  TYPES = %w[trade valuation settlement margin exercise expiry close_out].freeze
  TYPE_LABELS = { "trade" => "Trade", "valuation" => "Valuation", "settlement" => "Settlement", "margin" => "Margin / collateral",
                  "exercise" => "Exercise", "expiry" => "Expiry", "close_out" => "Close-out" }.freeze

  belongs_to :derivative_contract
  belongs_to :entity
  belongs_to :fund
  attr_readonly :fund_id # never moves to another fund (funds_api_security_policy_plan.md, B)
  belongs_to :portfolio_investment, optional: true
  belongs_to :import_upload, optional: true
  has_many :account_entries, as: :parent, dependent: :destroy

  validates :event_type, inclusion: { in: TYPES }
  validates :event_date, :idempotency_key, presence: true
  validates :value_cents, presence: true, if: -> { event_type == "valuation" }
  validate :not_before_trade_date

  def type_label
    TYPE_LABELS[event_type]
  end

  private

  # X21 — Error case: an event dated before the trade date
  def not_before_trade_date
    return unless derivative_contract && event_date && event_date < derivative_contract.trade_date

    errors.add(:event_date, "must be on or after the trade date")
  end
end
