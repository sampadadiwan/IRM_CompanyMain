class ChangeUnitTypeLengthInFundUnit < ActiveRecord::Migration[7.1]
  def change
    change_column :fund_units, :unit_type, :string, limit: 25
  end
end
