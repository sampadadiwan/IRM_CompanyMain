class ChangeArbitraryToCustomFlag < ActiveRecord::Migration[7.0]
  def change
    EntitySetting.update_all(arbitrary: "0")
    change_column :entity_settings, :arbitrary, :integer, default: 0
    rename_column :entity_settings, :arbitrary, :custom_flags
  end
end
