class AddEnablePortfolioToEntity < ActiveRecord::Migration[7.0]
  def change
    add_column :entities, :enable_fund_portfolios, :boolean, default: false
  end
end
