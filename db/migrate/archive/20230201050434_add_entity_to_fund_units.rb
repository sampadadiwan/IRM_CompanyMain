class AddEntityToFundUnits < ActiveRecord::Migration[7.0]
  def change
    add_reference :fund_units, :entity, null: false, foreign_key: true
    change_column :fund_units, :quantity, :decimal, precision: 20, scale: 2, default: "0.0"
  end
end
