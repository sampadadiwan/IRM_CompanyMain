class ChangeAccountEntryUniqIdx < ActiveRecord::Migration[7.1]
  def change
    remove_index :account_entries, name: "idx_account_entries_reporting_date_uniq"
    execute "ALTER TABLE account_entries ADD generated_deleted datetime(6) AS (ifNull(deleted_at, '1900-01-01 00:00:00')) NOT NULL"

    add_index :account_entries, [:capital_commitment_id, :name, :entry_type, :reporting_date, :cumulative, :generated_deleted],
        unique: true,
        name: "idx_account_entries_reporting_date_uniq"
  end
end
