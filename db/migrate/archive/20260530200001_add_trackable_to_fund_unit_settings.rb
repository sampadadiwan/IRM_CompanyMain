class AddTrackableToFundUnitSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :fund_unit_settings, :deleted_at, :datetime
    add_index :fund_unit_settings, :deleted_at
  end
end
