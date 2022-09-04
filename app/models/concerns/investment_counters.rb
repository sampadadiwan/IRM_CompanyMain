module InvestmentCounters
  extend ActiveSupport::Concern

  EQUITY_LIKE = %w[Equity Preferred Options Units].freeze

  included do
    # Counter Cache for funding_round.amount_raised_cents
    counter_culture :funding_round,
                    column_name: proc { |i| i.actual_scenario? ? 'amount_raised_cents' : nil },
                    delta_column: 'amount_cents'
    # Counter Cache for funding_round equity or preferred or options
    counter_culture :funding_round,
                    column_name: proc { |i| i.actual_scenario? && EQUITY_LIKE.include?(i.investment_instrument) ? i.investment_instrument.downcase : nil },
                    delta_column: 'quantity'
    # Counter Cache for entity equity or preferred or options
    counter_culture %i[funding_round entity],
                    column_name: proc { |i| i.actual_scenario? && EQUITY_LIKE.include?(i.investment_instrument) ? i.investment_instrument.downcase : nil },
                    delta_column: 'quantity'

    counter_culture :entity,
                    column_name: proc { |i| i.actual_scenario? ? 'investments_count' : nil }
    counter_culture :entity,
                    column_name: proc { |i| i.actual_scenario? ? 'total_investments' : nil },
                    delta_column: 'amount_cents'

    counter_culture :aggregate_investment,
                    column_name: proc { |i| EQUITY_LIKE.include?(i.investment_instrument) ? i.investment_instrument.downcase : nil },
                    delta_column: 'quantity'
  end

  def actual_scenario?
    true
  end
end
