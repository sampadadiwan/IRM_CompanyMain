class AddParentToAccountEntry < ActiveRecord::Migration[7.0]
  def change
    add_reference :account_entries, :parent, polymorphic: true, null: true
    remove_column :account_entries, :parent_account_entry_id
  end
end
