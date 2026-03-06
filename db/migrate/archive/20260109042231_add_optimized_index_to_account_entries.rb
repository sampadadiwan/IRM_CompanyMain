class AddOptimizedIndexToAccountEntries < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    # add_index :account_entries, [:fund_id, :reporting_date, :fund_formula_id, :deleted_at],
    #           name: 'idx_ae_fund_date_formula_deleted'
  end
end
