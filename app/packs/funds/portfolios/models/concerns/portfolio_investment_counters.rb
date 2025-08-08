module PortfolioInvestmentCounters
  extend ActiveSupport::Concern

  included do
    # We rollup net quantity to the API quantity, only for buys. This takes care of sells and transfers
    counter_culture :aggregate_portfolio_investment, column_name: proc { |r| r.buy? && r.non_proforma? ? "quantity" : nil }, delta_column: 'net_quantity', column_names: {
      ["portfolio_investments.quantity > ? and portfolio_investments.proforma = ?", 0, false] => 'quantity',
      ["portfolio_investments.quantity < ? and portfolio_investments.proforma = ?", 0, false] => nil
    }

    counter_culture :aggregate_portfolio_investment, column_name: proc { |r| r.non_proforma? ? "ex_expenses_amount_cents" : nil }, delta_column: 'ex_expenses_amount_cents', column_names: {
      ["portfolio_investments.proforma = ?", false] => 'ex_expenses_amount_cents'
    }

    counter_culture :aggregate_portfolio_investment, column_name: proc { |r| r.non_proforma? ? "transfer_amount_cents" : nil }, delta_column: 'transfer_amount_cents', column_names: {
      ["portfolio_investments.proforma = ?", false] => 'transfer_amount_cents'
    }
    counter_culture :aggregate_portfolio_investment, column_name: proc { |r| r.non_proforma? ? "transfer_quantity" : nil }, delta_column: 'transfer_quantity', column_names: {
      ["portfolio_investments.proforma = ?", false] => 'transfer_quantity'
    }

    counter_culture :aggregate_portfolio_investment, column_name: proc { |r| r.non_proforma? ? "cost_of_remaining_cents" : nil }, delta_column: 'cost_of_remaining_cents', column_names: {
      ["portfolio_investments.proforma = ?", false] => 'cost_of_remaining_cents'
    }
    counter_culture :aggregate_portfolio_investment, column_name: proc { |r| r.non_proforma? ? "unrealized_gain_cents" : nil }, delta_column: 'unrealized_gain_cents', column_names: {
      ["portfolio_investments.proforma = ?", false] => 'unrealized_gain_cents'
    }
    counter_culture :aggregate_portfolio_investment, column_name: proc { |r| r.non_proforma? ? "gain_cents" : nil }, delta_column: 'gain_cents', column_names: {
      ["portfolio_investments.proforma = ?", false] => 'gain_cents'
    }

    counter_culture :aggregate_portfolio_investment, column_name: proc { |r| r.non_proforma? ? "fmv_cents" : nil }, delta_column: 'fmv_cents', column_names: {
      ["portfolio_investments.proforma = ?", false] => 'fmv_cents'
    }

    # For sells, roll up the amount_cents to the aggregate portfolio investment sold_amount_cents
    counter_culture :aggregate_portfolio_investment, column_name: proc { |r| r.sell? && r.non_proforma? ? "sold_amount_cents" : nil }, delta_column: 'amount_cents', column_names: {
      ["portfolio_investments.quantity < ? and portfolio_investments.proforma = ?", 0, false] => 'sold_amount_cents'
    }

    counter_culture :aggregate_portfolio_investment, column_name: proc { |r| r.sell? && r.non_proforma? ? "sold_quantity" : nil }, delta_column: 'quantity', column_names: {
      ["portfolio_investments.quantity < ? and portfolio_investments.proforma = ?", 0, false] => 'sold_quantity'
    }

    # For buys, roll up the net_bought_amount_cents to the aggregate portfolio investment bought_amount_cents
    counter_culture :aggregate_portfolio_investment, column_name: proc { |r| r.buy? && r.non_proforma? ? "bought_amount_cents" : nil }, delta_column: 'amount_cents', column_names: {
      ["portfolio_investments.quantity > ? and portfolio_investments.proforma = ?", 0, false] => 'bought_amount_cents'
    }

    counter_culture :aggregate_portfolio_investment, column_name: proc { |r| r.buy? && r.non_proforma? ? "net_bought_amount_cents" : nil }, delta_column: 'net_bought_amount_cents', column_names: {
      ["portfolio_investments.quantity > ? and portfolio_investments.proforma = ?", 0, false] => 'net_bought_amount_cents'
    }

    counter_culture :aggregate_portfolio_investment, column_name: proc { |r| r.buy? && r.non_proforma? ? "bought_quantity" : nil }, delta_column: 'quantity', column_names: {
      ["portfolio_investments.quantity > ? and portfolio_investments.proforma = ?", 0, false] => 'bought_quantity'
    }

    counter_culture :aggregate_portfolio_investment, column_name: proc { |r| r.buy? && r.non_proforma? ? "instrument_currency_fmv_cents" : nil }, delta_column: 'instrument_currency_fmv_cents', column_names: {
      ["portfolio_investments.quantity > ? and portfolio_investments.proforma = ?", 0, false] => 'instrument_currency_fmv_cents'
    }
    counter_culture :aggregate_portfolio_investment, column_name: proc { |r| r.buy? && r.non_proforma? ? "instrument_currency_cost_of_remaining_cents" : nil }, delta_column: 'instrument_currency_cost_of_remaining_cents', column_names: {
      ["portfolio_investments.quantity > ? and portfolio_investments.proforma = ?", 0, false] => 'instrument_currency_cost_of_remaining_cents'
    }
    counter_culture :aggregate_portfolio_investment, column_name: proc { |r| r.buy? && r.non_proforma? ? "instrument_currency_unrealized_gain_cents" : nil }, delta_column: 'instrument_currency_unrealized_gain_cents', column_names: {
      ["portfolio_investments.quantity > ? and portfolio_investments.proforma = ?", 0, false] => 'instrument_currency_unrealized_gain_cents'
    }
  end
end
