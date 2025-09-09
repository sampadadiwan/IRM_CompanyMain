class AddIdxAeFundAllocAndDropAllocRunIdx < ActiveRecord::Migration[8.0]

  def up
    # Add composite index only if it's not already there (your first run likely added it)
    unless index_exists?(:account_entries, [:fund_id, :allocation_run_id], name: "idx_ae_fund_alloc")
      add_index :account_entries, [:fund_id, :allocation_run_id],
                name: "idx_ae_fund_alloc",
                algorithm: :inplace
    end

    # Drop single-column index if present
    if index_exists?(:account_entries, :allocation_run_id, name: "index_account_entries_on_allocation_run_id")
      remove_index :account_entries, name: "index_account_entries_on_allocation_run_id"
    end
  end

  def down
    # Recreate single-column index if missing
    unless index_exists?(:account_entries, :allocation_run_id, name: "index_account_entries_on_allocation_run_id")
      add_index :account_entries, :allocation_run_id, name: "index_account_entries_on_allocation_run_id"
    end

    # Remove composite index if present
    remove_index :account_entries, name: "idx_ae_fund_alloc" if
      index_exists?(:account_entries, [:fund_id, :allocation_run_id], name: "idx_ae_fund_alloc")
  end

end
