class AddFrequencyToEntitySettings < ActiveRecord::Migration[8.1]
  def change
    add_column :entity_settings, :db_dumps_frequency, :string, default: 'daily'
    add_column :entity_settings, :db_dumps_interval, :integer, default: 1
    add_column :entity_settings, :db_dumps_custom_days, :string
    add_index :documents, %i[owner_tag created_at]
  end
end
