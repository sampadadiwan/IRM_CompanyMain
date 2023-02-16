class UpdateUniqueIndexOnAccountEntries < ActiveRecord::Migration[7.0]
  def change
    remove_index :account_entries, name: "idx_account_entries_reporting_date_uniq"
    add_index :account_entries, [:fund_id, :capital_commitment_id, :name, :entry_type, :reporting_date],
    unique: true,
    name: "idx_account_entries_reporting_date_uniq"
  end
end
