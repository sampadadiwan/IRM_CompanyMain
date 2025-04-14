module PortfolioInvestmentCounters
  extend ActiveSupport::Concern

  included do
    # Roll up net quantity to quantity for buys (excluding snapshots)
    counter_culture :aggregate_portfolio_investment,
                    column_name: proc { |r| r.buy? && !r.snapshot ? "quantity" : nil },
                    delta_column: 'net_quantity',
                    column_names: {
                      ["portfolio_investments.quantity > ? AND portfolio_investments.snapshot = ?", 0, false] => 'quantity',
                      ["portfolio_investments.quantity < ? AND portfolio_investments.snapshot = ?", 0, false] => nil
                    }

    # Transfer-related counters
    counter_culture :aggregate_portfolio_investment,
                    column_name: 'transfer_amount_cents',
                    delta_column: 'transfer_amount_cents',
                    column_names: {
                      ["portfolio_investments.snapshot = ?", false] => 'transfer_amount_cents'
                    }

    counter_culture :aggregate_portfolio_investment,
                    column_name: 'transfer_quantity',
                    delta_column: 'transfer_quantity',
                    column_names: {
                      ["portfolio_investments.snapshot = ?", false] => 'transfer_quantity'
                    }

    # Other summary fields
    counter_culture :aggregate_portfolio_investment,
                    column_name: 'cost_of_remaining_cents',
                    delta_column: 'cost_of_remaining_cents',
                    column_names: {
                      ["portfolio_investments.snapshot = ?", false] => 'cost_of_remaining_cents'
                    }

    counter_culture :aggregate_portfolio_investment,
                    column_name: 'unrealized_gain_cents',
                    delta_column: 'unrealized_gain_cents',
                    column_names: {
                      ["portfolio_investments.snapshot = ?", false] => 'unrealized_gain_cents'
                    }

    counter_culture :aggregate_portfolio_investment,
                    column_name: 'gain_cents',
                    delta_column: 'gain_cents',
                    column_names: {
                      ["portfolio_investments.snapshot = ?", false] => 'gain_cents'
                    }

    counter_culture :aggregate_portfolio_investment,
                    column_name: 'fmv_cents',
                    delta_column: 'fmv_cents',
                    column_names: {
                      ["portfolio_investments.snapshot = ?", false] => 'fmv_cents'
                    }

    # Sell-related counters
    counter_culture :aggregate_portfolio_investment,
                    column_name: proc { |r| r.sell? && !r.snapshot ? "sold_amount_cents" : nil },
                    delta_column: 'amount_cents',
                    column_names: {
                      ["portfolio_investments.quantity < ? AND portfolio_investments.snapshot = ?", 0, false] => 'sold_amount_cents'
                    }

    counter_culture :aggregate_portfolio_investment,
                    column_name: proc { |r| r.sell? && !r.snapshot ? "sold_quantity" : nil },
                    delta_column: 'quantity',
                    column_names: {
                      ["portfolio_investments.quantity < ? AND portfolio_investments.snapshot = ?", 0, false] => 'sold_quantity'
                    }

    # Buy-related counters
    counter_culture :aggregate_portfolio_investment,
                    column_name: proc { |r| r.buy? && !r.snapshot ? "bought_amount_cents" : nil },
                    delta_column: 'amount_cents',
                    column_names: {
                      ["portfolio_investments.quantity > ? AND portfolio_investments.snapshot = ?", 0, false] => 'bought_amount_cents'
                    }

    counter_culture :aggregate_portfolio_investment,
                    column_name: proc { |r| r.buy? && !r.snapshot ? "net_bought_amount_cents" : nil },
                    delta_column: 'net_bought_amount_cents',
                    column_names: {
                      ["portfolio_investments.quantity > ? AND portfolio_investments.snapshot = ?", 0, false] => 'net_bought_amount_cents'
                    }

    counter_culture :aggregate_portfolio_investment,
                    column_name: proc { |r| r.buy? && !r.snapshot ? "bought_quantity" : nil },
                    delta_column: 'quantity',
                    column_names: {
                      ["portfolio_investments.quantity > ? AND portfolio_investments.snapshot = ?", 0, false] => 'bought_quantity'
                    }
  end
end
