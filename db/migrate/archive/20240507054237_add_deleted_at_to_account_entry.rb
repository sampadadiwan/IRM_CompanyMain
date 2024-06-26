class AddDeletedAtToAccountEntry < ActiveRecord::Migration[7.1]
  def change
    add_column :account_entries, :deleted_at, :datetime
    add_index :account_entries, :deleted_at
  end
end
