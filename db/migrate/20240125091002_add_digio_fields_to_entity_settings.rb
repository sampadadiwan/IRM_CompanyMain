class AddDigioFieldsToEntitySettings < ActiveRecord::Migration[7.1]
  def change
    unless column_exists?(:entity_settings, :digio_client_id)
      add_column :entity_settings, :digio_client_id, :string
    end
    unless column_exists?(:entity_settings, :digio_client_secret)
      add_column :entity_settings, :digio_client_secret, :string
    end
    unless column_exists?(:entity_settings, :digio_auth_token)
      add_column :entity_settings, :digio_cutover_date, :datetime
    end

    unless column_exists?(:documents, :digio_cutover_date)
      add_column :documents, :sent_for_esign_date, :datetime
    end
  end
end
