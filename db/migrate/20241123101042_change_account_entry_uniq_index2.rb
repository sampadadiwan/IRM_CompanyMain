class ChangeAccountEntryUniqIndex2 < ActiveRecord::Migration[7.1]
  def change
    remove_index :account_entries, name: "idx_account_entries_reporting_date_uniq"
    add_index :account_entries, ["capital_commitment_id", "name", "entry_type", "parent_id", "parent_type", "reporting_date", "cumulative", "generated_deleted"], unique: true
  end
end
