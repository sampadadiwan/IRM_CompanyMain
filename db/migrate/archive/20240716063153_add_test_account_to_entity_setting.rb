class AddTestAccountToEntitySetting < ActiveRecord::Migration[7.1]
  def change
    add_column :entity_settings, :test_account, :boolean, default: false
  end
end
