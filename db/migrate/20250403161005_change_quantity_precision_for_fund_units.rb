class ChangeQuantityPrecisionForFundUnits < ActiveRecord::Migration[8.0]
  def change
    change_column :fund_units, :quantity, :decimal, precision: 26, scale: 8, null: false, default: 0.0
  end
end
