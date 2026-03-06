class AddStageToPortfolioInvestment < ActiveRecord::Migration[8.0]
  def change
    add_column :portfolio_investments, :stage, :string
  end
end
