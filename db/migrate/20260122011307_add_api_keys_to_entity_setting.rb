class AddApiKeysToEntitySetting < ActiveRecord::Migration[8.1]
  def change
    add_column :entity_settings, :openai_api_key, :string
    add_column :entity_settings, :gemini_api_key, :string
  end
end
