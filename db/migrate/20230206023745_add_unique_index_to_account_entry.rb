class AddUniqueIndexToAccountEntry < ActiveRecord::Migration[7.0]
  def change
    add_index :account_entries, [:capital_commitment_id, :name, :entry_type, :reporting_date],
        unique: true,
        name: "idx_account_entries_reporting_date_uniq"
  end
end
