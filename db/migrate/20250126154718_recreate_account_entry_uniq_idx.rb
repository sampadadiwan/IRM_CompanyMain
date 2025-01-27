class RecreateAccountEntryUniqIdx < ActiveRecord::Migration[7.2]
  def change
    # Drop the index
    remove_index :account_entries, name: "idx_on_capital_commitment_id_name_entry_type_parent_d92f7fd428"
    # Recreate the index
    add_index :account_entries, ["capital_commitment_id", "name", "entry_type", "reporting_date", "cumulative", "generated_deleted"]
  end
end
