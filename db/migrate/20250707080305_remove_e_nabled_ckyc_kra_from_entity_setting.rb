class RemoveENabledCkycKraFromEntitySetting < ActiveRecord::Migration[8.0]
  def change
    if column_exists?(:entity_settings, :ckyc_enabled)
      remove_column :entity_settings, :ckyc_enabled
    end

    if column_exists?(:entity_settings, :kra_enabled)
      remove_column :entity_settings, :kra_enabled
    end
  end
end
