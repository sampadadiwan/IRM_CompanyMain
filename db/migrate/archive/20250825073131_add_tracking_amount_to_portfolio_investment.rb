class AddTrackingAmountToPortfolioInvestment < ActiveRecord::Migration[8.0]
  def change
    add_column :portfolio_investments, :tracking_amount_cents, :decimal, precision: 20, scale: 2, default: 0
    add_column :portfolio_investments, :tracking_fmv_cents, :decimal, precision: 20, scale: 2, default: 0
  end
end
