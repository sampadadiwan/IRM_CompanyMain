class AddResidualAmountToPortfolioInvestment < ActiveRecord::Migration[7.1]
  def change
    add_column :portfolio_investments, :net_amount_cents, :decimal, precision: 20, scale: 2
  end
end
