class AddFieldsToEntitySettings < ActiveRecord::Migration[7.1]
  def change
    unless column_exists? :entity_settings, :ckyc_enabled
      Rails.logger.info "Adding ckyc_enabled"
      add_column :entity_settings, :ckyc_enabled, :boolean, default: false
    end
    unless column_exists? :entity_settings, :kra_enabled
      Rails.logger.info "Adding kra_enabled"
      add_column :entity_settings, :kra_enabled, :boolean, default: false
    end
    if column_exists? :entity_settings, :ckyc_kra_enabled
      Rails.logger.info "Migrating ckyc_kra_enabled"
      EntitySetting.where(ckyc_kra_enabled: true).update_all(ckyc_enabled: true)
      # remove_column :entity_settings, :ckyc_kra_enabled
    end
  end
end
