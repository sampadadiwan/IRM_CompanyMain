class AddStartOfFinancialYearDateToEntitySetting < ActiveRecord::Migration[8.1]
  def change
    add_column :entity_settings, :month_offset_for_fy, :integer, default: nil
  end
end
