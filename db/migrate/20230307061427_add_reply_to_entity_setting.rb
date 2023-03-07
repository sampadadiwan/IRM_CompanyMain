class AddReplyToEntitySetting < ActiveRecord::Migration[7.0]
  def change
    add_column :entity_settings, :reply_to, :string
    add_column :entity_settings, :cc, :string
  end
end
