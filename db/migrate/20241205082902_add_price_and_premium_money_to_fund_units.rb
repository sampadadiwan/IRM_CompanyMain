class AddPriceAndPremiumMoneyToFundUnits < ActiveRecord::Migration[7.2]
  def change
    unless column_exists? :fund_units, :price_cents
      add_column :fund_units, :price_cents, :decimal, precision: 20, scale: 2, default: 0, null: false
    end
    unless column_exists? :fund_units, :premium_cents
      add_column :fund_units, :premium_cents, :decimal, precision: 20, scale: 2, default: 0, null: false
    end
    migrate_fund_units_data

    # remove columns later after migration is verified
    if column_exists? :fund_units, :price
      rename_column :fund_units, :price, :price_old
    end
    if column_exists? :fund_units, :premium
      rename_column :fund_units, :premium, :premium_old
    end
  end

  def migrate_fund_units_data
    FundUnit.all.each do |fund_unit|
      fund_unit.update_columns(price_cents: fund_unit.price * 100, premium_cents: fund_unit.premium * 100)
    end
  end
end
