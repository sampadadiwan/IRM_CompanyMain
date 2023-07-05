class ChangeAccountEntryUniqIndex < ActiveRecord::Migration[7.0]
  def change
    remove_index :account_entries, name: "idx_account_entries_reporting_date_uniq"
    add_index :account_entries, [:capital_commitment_id, :name, :entry_type, :reporting_date, :cumulative],
        unique: true,
        name: "idx_account_entries_reporting_date_uniq"
  end
end
