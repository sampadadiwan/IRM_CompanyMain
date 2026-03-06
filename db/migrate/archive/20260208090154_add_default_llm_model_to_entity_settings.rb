class AddDefaultLlmModelToEntitySettings < ActiveRecord::Migration[8.1]
  def change
    add_column :entity_settings, :default_llm_model, :string
    add_column :entity_settings, :anthropic_api_key, :string
    add_column :entity_settings, :openrouter_api_key, :string
  end
end
