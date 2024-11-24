class SetPortfolioIncomeDefault < ActiveRecord::Migration[7.2]
  def change
    change_column_default :aggregate_portfolio_investments, :portfolio_income_cents, 0
  end
end
