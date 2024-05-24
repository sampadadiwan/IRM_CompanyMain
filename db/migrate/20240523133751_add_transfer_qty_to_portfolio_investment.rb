class AddTransferQtyToPortfolioInvestment < ActiveRecord::Migration[7.1]
  def change
    add_column :portfolio_investments, :transfer_quantity, :decimal, precision: 20, scale: 2, default: 0
  end
end
