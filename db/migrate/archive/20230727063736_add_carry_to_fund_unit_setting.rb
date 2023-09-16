class AddCarryToFundUnitSetting < ActiveRecord::Migration[7.0]
  def change
    add_column :fund_unit_settings, :carry, :decimal, precision: 20, scale: 2, default: "0.0"
  end
end
