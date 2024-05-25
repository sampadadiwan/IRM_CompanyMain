class AddIndexToAccountEntry < ActiveRecord::Migration[7.1]
  def change
    add_index :account_entries, :entry_type
    add_index :account_entries, :name
    add_index :account_entries, :reporting_date
  end
end
