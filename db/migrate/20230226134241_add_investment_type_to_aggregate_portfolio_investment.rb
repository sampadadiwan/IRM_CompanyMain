class AddInvestmentTypeToAggregatePortfolioInvestment < ActiveRecord::Migration[7.0]
  def change
    add_column :aggregate_portfolio_investments, :investment_type, :string, limit: 20
    change_column :portfolio_investments, :investment_type, :string, limit: 20
  end
end
