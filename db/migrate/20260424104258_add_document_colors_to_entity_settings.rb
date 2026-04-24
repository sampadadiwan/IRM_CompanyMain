class AddDocumentColorsToEntitySettings < ActiveRecord::Migration[8.1]
  def change
    unless column_exists?(:entity_settings, :document_colors)
      add_column :entity_settings, :document_colors, :json
    end
  end
end
