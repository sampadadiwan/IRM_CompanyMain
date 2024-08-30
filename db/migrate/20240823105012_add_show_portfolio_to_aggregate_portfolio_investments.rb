class AddShowPortfolioToAggregatePortfolioInvestments < ActiveRecord::Migration[7.1]
  def change
    unless column_exists?(:aggregate_portfolio_investments, :show_portfolio)
      add_column :aggregate_portfolio_investments, :show_portfolio, :boolean, default: false
    end
  end
end
