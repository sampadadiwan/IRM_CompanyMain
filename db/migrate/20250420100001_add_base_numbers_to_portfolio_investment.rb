class AddBaseNumbersToPortfolioInvestment < ActiveRecord::Migration[8.0]
  def change
    add_column :portfolio_investments, :base_fmv_cents, :decimal, precision: 20, scale: 2, default: 0
    add_column :aggregate_portfolio_investments, :base_fmv_cents, :decimal, precision: 20, scale: 2, default: 0
    add_column :portfolio_investments, :base_cost_of_remaining_cents, :decimal, precision: 20, scale: 2, default: 0
    add_column :aggregate_portfolio_investments, :base_cost_of_remaining_cents, :decimal, precision: 20, scale: 2, default: 0
    add_column :portfolio_investments, :base_unrealized_gain_cents, :decimal, precision: 20, scale: 2, default: 0
    add_column :aggregate_portfolio_investments, :base_unrealized_gain_cents, :decimal, precision: 20, scale: 2, default: 0
  end
end
