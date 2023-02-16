class ChangeNameForAccountEntry < ActiveRecord::Migration[7.0]
  def change
    change_column :account_entries, :name, :string, limit: 100
    change_column :account_entries, :period, :string, limit: 25
  end
end
