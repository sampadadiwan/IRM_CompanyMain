class ChangeFusManagementFee < ActiveRecord::Migration[7.0]
  def change
    change_column :fund_unit_settings, :management_fee, :decimal, precision: 20, scale: 4, default: 0.0
    change_column :fund_unit_settings, :setup_fee, :decimal, precision: 20, scale: 4, default: 0.0
    change_column :fund_unit_settings, :carry, :decimal, precision: 20, scale: 4, default: 0.0
  end
end
