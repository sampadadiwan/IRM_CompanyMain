class AddFicodeToEntitySettings < ActiveRecord::Migration[7.0]
  def change
    add_column :entity_settings, :fi_code, :string
    add_column :entity_settings, :ckyc_kra_enabled, :boolean, default: false
  end
end
