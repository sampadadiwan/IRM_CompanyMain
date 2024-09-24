class AddRegEnvToEntitySetting < ActiveRecord::Migration[7.1]
  def change
    add_column :entity_settings, :regulatory_env, :string, limit: 20, default: "SEBI"
  end
end
