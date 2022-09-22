module InvestmentScopes
  extend ActiveSupport::Concern

  included do
    scope :prospective, -> { where(investor_type: "Prospective") }
    scope :shareholders, -> { where(investor_type: "Shareholder") }
    scope :debt, -> { where(investment_instrument: "Debt") }
    scope :not_debt, -> { where("investment_instrument <> 'Debt'") }
    scope :equity, -> { where(investment_instrument: "Equity") }
    scope :preferred, -> { where(investment_instrument: "Preferred") }
    scope :options, -> { where(investment_instrument: "Options") }
    scope :equity_or_pref, -> { where(investment_instrument: %w[Equity Preferred]) }
    scope :options_or_esop, -> { where(investment_instrument: %w[Options]) }
    scope :debt, -> { where(investment_instrument: "Debt") }

    scope :for, lambda { |holding|
                  where(employee_holdings: true, funding_round_id: holding.funding_round_id,
                        investment_instrument: holding.investment_instrument,
                        category: holding.holding_type)
                }
  end
end
