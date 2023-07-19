class AddBccToEntitySetting < ActiveRecord::Migration[7.0]
  def change
    add_column :entity_settings, :entity_bcc, :string
    add_column :documents, :send_email, :boolean, default: true
  end
end
