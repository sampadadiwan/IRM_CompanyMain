class AddAppendToEntitySetting < ActiveRecord::Migration[7.1]
  def change
    add_column :entity_settings, :append_to_commitment_agreement, :string
  end
end
