class AddPortfolioIncomeToAggregatePortfolioInvestment < ActiveRecord::Migration[7.1]
  def change
    add_column :aggregate_portfolio_investments, :portfolio_income_cents, :decimal, precision: 20, scale: 2, default: 0, null: false
    PortfolioCashflow.counter_culture_fix_counts
  end
end
