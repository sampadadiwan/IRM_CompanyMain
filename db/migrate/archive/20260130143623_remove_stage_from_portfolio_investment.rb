class RemoveStageFromPortfolioInvestment < ActiveRecord::Migration[8.1]
  def change
    if column_exists?(:portfolio_investments, :stage)
      remove_column :portfolio_investments, :stage, :string
    end
  end
end
