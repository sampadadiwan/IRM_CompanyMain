class AddPercentageToCapitalRemittance < ActiveRecord::Migration[7.0]
  def change
    add_column :capital_remittances, :percentage, :decimal, precision: 10, scale: 2, default: 0.0
  end
end
