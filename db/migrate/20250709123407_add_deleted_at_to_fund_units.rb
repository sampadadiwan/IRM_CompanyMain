class AddDeletedAtToFundUnits < ActiveRecord::Migration[8.0]
  def change
    add_column :fund_units, :deleted_at, :datetime
    add_index :fund_units, :deleted_at

    add_column :fund_units, :amount_cents, :decimal, precision: 20, scale: 2, default: 0
    add_column :capital_commitments, :total_units_amount_cents, :decimal, precision: 20, scale: 2, default: 0

    FundUnit.all.each do |fund_unit|
      fund_unit.update_column(:amount_cents, fund_unit.quantity * (fund_unit.price_cents + fund_unit.premium_cents))
    end

    FundUnit.counter_culture_fix_counts
  end
end
