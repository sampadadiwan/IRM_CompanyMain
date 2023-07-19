class AddSandboxNumbersToEntitySetting < ActiveRecord::Migration[7.0]
  def change
    add_column :entity_settings, :sandbox_numbers, :string, if_not_exists: true
  end
end
