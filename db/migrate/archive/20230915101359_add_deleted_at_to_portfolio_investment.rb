class AddDeletedAtToPortfolioInvestment < ActiveRecord::Migration[7.0]
  def change
    add_column :portfolio_investments, :deleted_at, :datetime
    add_index :portfolio_investments, :deleted_at
  end
end
