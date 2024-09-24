class AddBoughtAmountToPortfolioInvestment < ActiveRecord::Migration[7.1]
  def change
    add_column :portfolio_investments, :net_bought_amount_cents, :decimal, precision: 20, scale: 2
    add_column :portfolio_investments, :net_bought_quantity, :decimal, precision: 20, scale: 2
  end
end
