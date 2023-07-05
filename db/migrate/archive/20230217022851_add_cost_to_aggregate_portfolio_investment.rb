class AddCostToAggregatePortfolioInvestment < ActiveRecord::Migration[7.0]
  def change
    add_column :aggregate_portfolio_investments, :cost_cents, :decimal, precision: 20, scale: 2, default: "0.0"
  end
end
