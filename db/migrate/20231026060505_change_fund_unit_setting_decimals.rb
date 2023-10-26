class ChangeFundUnitSettingDecimals < ActiveRecord::Migration[7.1]
  def change
    change_column :fund_unit_settings, :management_fee, :decimal, precision: 24, scale: 8, default: "0.0"
    change_column :fund_unit_settings, :setup_fee, :decimal, precision: 24, scale: 8, default: "0.0"
    change_column :fund_unit_settings, :carry, :decimal, precision: 24, scale: 8, default: "0.0"
  end
end
