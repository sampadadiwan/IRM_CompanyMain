class AddUniqueIndexToAccounts < ActiveRecord::Migration[6.0]
  def change
    add_index :account_entries, [:name, :fund_id, :capital_commitment_id, :entry_type, :reporting_date, :cumulative, :deleted_at], unique: true, name: 'index_accounts_on_unique_fields'
  end
end
