module InvestmentCounters
  extend ActiveSupport::Concern

  EQUITY_LIKE = %w[Equity Preferred Options Units].freeze

  included do
    # Counter Cache for funding_round.amount_raised_cents
    counter_culture :funding_round,
                    column_name: 'amount_raised_cents',
                    delta_column: 'amount_cents'
    # Counter Cache for funding_round equity or preferred or options
    counter_culture :funding_round,
                    column_name: proc { |i| EQUITY_LIKE.include?(i.investment_instrument) ? i.investment_instrument.downcase : nil },
                    delta_column: 'quantity'
    # Counter Cache for entity equity or preferred or options
    counter_culture %i[funding_round entity],
                    column_name: proc { |i| EQUITY_LIKE.include?(i.investment_instrument) ? i.investment_instrument.downcase : nil },
                    delta_column: 'quantity'

    counter_culture :entity,
                    column_name: 'investments_count'
    counter_culture :entity,
                    column_name: 'total_investments',
                    delta_column: 'amount_cents'

    counter_culture :aggregate_investment,
                    column_name: proc { |i| EQUITY_LIKE.include?(i.investment_instrument) ? i.investment_instrument.downcase : nil },
                    delta_column: 'quantity'

    counter_culture :aggregate_investment,
                    column_name: proc { |i| i.investment_instrument == "Preferred" ? 'preferred_converted_qty' : nil },
                    delta_column: 'preferred_converted_qty'
  end
end
