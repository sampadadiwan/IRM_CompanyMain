class AddApiToPortfolioInvestment < ActiveRecord::Migration[7.0]
  def change
    add_reference :portfolio_investments, :aggregate_portfolio_investment, null: false, foreign_key: true
    add_column :aggregate_portfolio_investments, :portfolio_company_name, :string, limit: 100
  end
end
