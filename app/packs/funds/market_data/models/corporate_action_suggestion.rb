# A split, bonus or dividend the price provider reported for a Market instrument. A person
# confirms it — creating the same Stock Adjustment (split/bonus) or portfolio cashflows (dividend)
# they would enter by hand — or dismisses it. Never suggested twice (provider_ref is unique).
# openspec/changes/fund-market-data — design card ②. Worked examples H10, E46, E47.
class CorporateActionSuggestion < ApplicationRecord
  class InvalidTransition < StandardError; end

  KINDS = %w[split bonus dividend].freeze

  belongs_to :entity
  belongs_to :investment_instrument
  belongs_to :resolved_by, class_name: "User", optional: true
  belongs_to :stock_adjustment, optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: %w[pending confirmed dismissed] }

  scope :pending, -> { where(status: "pending") }

  after_create_commit :notify_fund_accounting

  # H10 — confirm into the record a person would create by hand
  def confirm!(user)
    with_lock do
      raise InvalidTransition, "Already resolved" unless status == "pending"

      if kind == "dividend"
        create_dividend_cashflows
      else
        adjustment = StockAdjustment.create!(entity:, portfolio_company: investment_instrument.portfolio_company,
                                             investment_instrument:, user:, adjustment: ratio,
                                             notes: "#{subject} (ex-date #{ex_date}) — confirmed from a suggested corporate action")
        self.stock_adjustment = adjustment
      end
      update!(status: "confirmed", resolved_by: user, resolved_at: Time.current)
    end
  end

  # E46 — dismissed suggestions are kept so the same action is never suggested again
  def dismiss!(user)
    with_lock do
      raise InvalidTransition, "Already resolved" unless status == "pending"

      update!(status: "dismissed", resolved_by: user, resolved_at: Time.current)
    end
  end

  private

  # One cashflow per fund holding the instrument on the ex-date: dividend per share × shares held
  def create_dividend_cashflows
    AggregatePortfolioInvestment.where(entity_id:, investment_instrument_id:).find_each do |api|
      qty = api.net_quantity_on(ex_date)
      next unless qty.positive?

      PortfolioCashflow.create!(entity_id:, fund_id: api.fund_id, aggregate_portfolio_investment: api,
                                portfolio_company_id: api.portfolio_company_id, investment_instrument_id:,
                                payment_date: ex_date, amount_cents: qty * amount_per_share_cents, tag: "Dividend",
                                notes: "#{subject} — confirmed from a suggested corporate action")
    end
  end

  def notify_fund_accounting
    recipients = User.where(entity_id:, active: true).with_tag("FundAccounting").to_a
    return if recipients.empty?

    MarketDataOpsNotifier.with(record: self, entity_id:, email_method: "corporate_action_suggested").deliver_later(recipients)
  end
end
