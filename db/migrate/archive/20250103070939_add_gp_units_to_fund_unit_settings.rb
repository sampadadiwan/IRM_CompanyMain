class AddGpUnitsToFundUnitSettings < ActiveRecord::Migration[7.2]
  def change
    unless column_exists?(:fund_unit_settings, :gp_units)
      add_column :fund_unit_settings, :gp_units, :boolean, default: false
    end
  end
end
