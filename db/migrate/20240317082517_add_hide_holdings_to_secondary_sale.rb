class AddHideHoldingsToSecondarySale < ActiveRecord::Migration[7.1]
  def change
    add_column :secondary_sales, :show_holdings, :boolean, default: true
  end
end
