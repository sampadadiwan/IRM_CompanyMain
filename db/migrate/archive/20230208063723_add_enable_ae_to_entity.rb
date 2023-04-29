class AddEnableAeToEntity < ActiveRecord::Migration[7.0]
  def change
    add_column :entities, :enable_account_entries, :boolean, default: false
    add_column :entities, :enable_units, :boolean, default: false
  end
end
