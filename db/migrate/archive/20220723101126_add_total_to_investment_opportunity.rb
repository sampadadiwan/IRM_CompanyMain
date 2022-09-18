class AddTotalToInvestmentOpportunity < ActiveRecord::Migration[7.0]
  def change
    add_column :investment_opportunities, :eoi_amount_cents, :decimal, precision: 15, scale: 2, default: "0.0"
  end
end
