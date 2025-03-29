
class AddAllocationRunToAccountEntry < ActiveRecord::Migration[8.0]
  def change
    add_column :account_entries, :allocation_run_id, :bigint, null: true
    add_index :account_entries, :allocation_run_id
  end
end
