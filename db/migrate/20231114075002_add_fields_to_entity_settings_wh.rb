class AddFieldsToEntitySettingsWh < ActiveRecord::Migration[7.1]
  def change
    unless column_exists? :entity_settings, :whatsapp_token
      add_column :entity_settings, :whatsapp_token, :text
    end
    unless column_exists? :entity_settings, :whatsapp_endpoint
      add_column :entity_settings, :whatsapp_endpoint, :string
    end
    unless column_exists? :entity_settings, :whatsapp_templates
      add_column :entity_settings, :whatsapp_templates, :json
    end
  end
end
