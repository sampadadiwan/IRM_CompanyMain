class AddPriceToFundUnits < ActiveRecord::Migration[7.0]
  def change
    add_column :capital_commitments, :total_fund_units_quantity, :decimal, precision: 20, scale: 2, default: "0.0"
    add_column :fund_units, :price, :decimal, precision: 20, scale: 2, default: "0.0"
    add_reference :fund_units, :owner, polymorphic: true, null: true
  end
end
