class AlterPercentageCdp < ActiveRecord::Migration[7.0]
  def change
    change_column :capital_distribution_payments, :percentage, :decimal, precision: 11, scale: 8, default: "0.0"
  end
end
