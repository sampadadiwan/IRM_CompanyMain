class AddShowPortfoliosToFund < ActiveRecord::Migration[7.1]
  def change
    add_column :funds, :show_portfolios, :boolean, default: false
  end
end
