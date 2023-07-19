class AddCostOfSoldToPortfolioAttribution < ActiveRecord::Migration[7.0]
  def change
    add_column :portfolio_attributions, :cost_of_sold_cents, :decimal, precision: 20, scale: 2, default: 0
  end
end
