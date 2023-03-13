class AddAttributionToPortfolioInvestment < ActiveRecord::Migration[7.0]
  def change
    add_column :portfolio_investments, :sold_quantity, :decimal, precision: 20, scale: 2, default: "0.0"
    add_column :portfolio_investments, :net_quantity, :decimal, precision: 20, scale: 2, default: "0.0"
    add_column :portfolio_investments, :cost_of_sold_cents, :decimal, precision: 20, scale: 2, default: "0.0"
    add_column :portfolio_investments, :gain_cents, :decimal, precision: 20, scale: 2, default: "0.0"
  end
end
