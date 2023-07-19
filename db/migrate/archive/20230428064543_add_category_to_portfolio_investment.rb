class AddCategoryToPortfolioInvestment < ActiveRecord::Migration[7.0]
  def change
    add_column :portfolio_investments, :category, :string, limit: 10, null: true
    add_column :portfolio_investments, :sub_category, :string, limit: 100, null: true
  end
end
