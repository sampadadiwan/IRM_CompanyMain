class AddDistributionToPortfolioInvestment < ActiveRecord::Migration[8.0]
  def change
    add_reference :portfolio_investments, :capital_distribution, null: true, foreign_key: true
  end
end
