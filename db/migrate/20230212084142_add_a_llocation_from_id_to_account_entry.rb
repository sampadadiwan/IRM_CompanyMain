class AddALlocationFromIdToAccountEntry < ActiveRecord::Migration[7.0]
  def change
    add_reference :account_entries, :parent_account_entry, null: true, foreign_key: {to_table: :account_entries}
  end
end
