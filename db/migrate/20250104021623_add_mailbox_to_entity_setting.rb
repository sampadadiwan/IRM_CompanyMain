class AddMailboxToEntitySetting < ActiveRecord::Migration[7.2]
  def change
    add_column :entity_settings, :mailbox, :string, limit: 30
  end
end
