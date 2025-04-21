module PortfolioInvestmentCounters
  extend ActiveSupport::Concern

  included do
    # We rollup net quantity to the API quantity, only for buys. This takes care of sells and transfers
    counter_culture :aggregate_portfolio_investment, column_name: proc { |r| r.buy? ? "quantity" : nil }, delta_column: 'net_quantity', column_names: {
      ["portfolio_investments.quantity > ?", 0] => 'quantity',
      ["portfolio_investments.quantity < ?", 0] => nil
    }

    counter_culture :aggregate_portfolio_investment, column_name: 'transfer_amount_cents', delta_column: 'transfer_amount_cents'
    counter_culture :aggregate_portfolio_investment, column_name: 'transfer_quantity', delta_column: 'transfer_quantity'

    counter_culture :aggregate_portfolio_investment, column_name: 'cost_of_remaining_cents', delta_column: 'cost_of_remaining_cents'
    counter_culture :aggregate_portfolio_investment, column_name: 'unrealized_gain_cents', delta_column: 'unrealized_gain_cents'
    counter_culture :aggregate_portfolio_investment, column_name: 'gain_cents', delta_column: 'gain_cents'

    counter_culture :aggregate_portfolio_investment, column_name: 'fmv_cents', delta_column: 'fmv_cents'

    # For sells, roll up the amount_cents to the aggregate portfolio investment sold_amount_cents
    counter_culture :aggregate_portfolio_investment, column_name: proc { |r| r.sell? ? "sold_amount_cents" : nil }, delta_column: 'amount_cents', column_names: {
      ["portfolio_investments.quantity < ?", 0] => 'sold_amount_cents'
    }

    counter_culture :aggregate_portfolio_investment, column_name: proc { |r| r.sell? ? "sold_quantity" : nil }, delta_column: 'quantity', column_names: {
      ["portfolio_investments.quantity < ?", 0] => 'sold_quantity'
    }

    # For buys, roll up the net_bought_amount_cents to the aggregate portfolio investment bought_amount_cents
    counter_culture :aggregate_portfolio_investment, column_name: proc { |r| r.buy? ? "bought_amount_cents" : nil }, delta_column: 'amount_cents', column_names: {
      ["portfolio_investments.quantity > ?", 0] => 'bought_amount_cents'
    }

    counter_culture :aggregate_portfolio_investment, column_name: proc { |r| r.buy? ? "net_bought_amount_cents" : nil }, delta_column: 'net_bought_amount_cents', column_names: {
      ["portfolio_investments.quantity > ?", 0] => 'net_bought_amount_cents'
    }

    counter_culture :aggregate_portfolio_investment, column_name: proc { |r| r.buy? ? "bought_quantity" : nil }, delta_column: 'quantity', column_names: {
      ["portfolio_investments.quantity > ?", 0] => 'bought_quantity'
    }

    counter_culture :aggregate_portfolio_investment, column_name: proc { |r| r.buy? ? "instrument_currency_fmv_cents" : nil }, delta_column: 'instrument_currency_fmv_cents', column_names: {
      ["portfolio_investments.quantity > ?", 0] => 'instrument_currency_fmv_cents'
    }
    counter_culture :aggregate_portfolio_investment, column_name: proc { |r| r.buy? ? "instrument_currency_cost_of_remaining_cents" : nil }, delta_column: 'instrument_currency_cost_of_remaining_cents', column_names: {
      ["portfolio_investments.quantity > ?", 0] => 'instrument_currency_cost_of_remaining_cents'
    }
    counter_culture :aggregate_portfolio_investment, column_name: proc { |r| r.buy? ? "instrument_currency_unrealized_gain_cents" : nil }, delta_column: 'instrument_currency_unrealized_gain_cents', column_names: {
      ["portfolio_investments.quantity > ?", 0] => 'instrument_currency_unrealized_gain_cents'
    }
  end
end
