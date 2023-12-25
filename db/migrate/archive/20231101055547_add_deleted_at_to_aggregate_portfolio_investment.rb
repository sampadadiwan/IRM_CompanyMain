class AddDeletedAtToAggregatePortfolioInvestment < ActiveRecord::Migration[7.1]
  def change
    add_column :aggregate_portfolio_investments, :deleted_at, :datetime
    add_index :aggregate_portfolio_investments, :deleted_at
  end
end
