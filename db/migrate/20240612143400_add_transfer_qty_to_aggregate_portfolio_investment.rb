class AddTransferQtyToAggregatePortfolioInvestment < ActiveRecord::Migration[7.1]
  def change
    add_column :aggregate_portfolio_investments, :transfer_amount_cents, :decimal, precision: 20, scale: 2, default: 0
    add_column :portfolio_investments, :transfer_amount_cents, :decimal, precision: 20, scale: 2, default: 0

    # To ensure transfer_amount_cents rollups
    PortfolioInvestment.where("transfer_quantity > 0").each do |pi| 
      pi.save
      pi.api.save
    end
  end
end
