class AddEsignProviderToEntitySetting < ActiveRecord::Migration[7.1]
  def change
    unless column_exists?(:entity_settings, :esign_provider)
      add_column :entity_settings, :esign_provider, :string, limit: 15, default: "Digio"
    end
  end
end
