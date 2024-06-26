class ChangeUnitTypesInFund < ActiveRecord::Migration[7.1]
  def change
    change_column :funds, :unit_types, :string, limit: 255
    change_column :fund_unit_settings, :name, :string, limit: 25
  end
end
