class AddBoughtSoldToAggregatePortfolioInvestment < ActiveRecord::Migration[7.0]
  def change
    add_column :aggregate_portfolio_investments, :bought_quantity, :decimal, precision: 20, scale: 2, default: "0.0"
    add_column :aggregate_portfolio_investments, :bought_amount_cents, :decimal, precision: 20, scale: 2, default: "0.0"
    add_column :aggregate_portfolio_investments, :sold_quantity, :decimal, precision: 20, scale: 2, default: "0.0"
    add_column :aggregate_portfolio_investments, :sold_amount_cents, :decimal, precision: 20, scale: 2, default: "0.0"
  end
end
