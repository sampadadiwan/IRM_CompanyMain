class AddDeletedAtToFund < ActiveRecord::Migration[7.0]
  def change
    add_column :funds, :deleted_at, :datetime
    add_index :funds, :deleted_at
    add_column :capital_commitments, :deleted_at, :datetime
    add_index :capital_commitments, :deleted_at
    add_column :capital_calls, :deleted_at, :datetime
    add_index :capital_calls, :deleted_at
    add_column :capital_remittances, :deleted_at, :datetime
    add_index :capital_remittances, :deleted_at
    add_column :capital_distributions, :deleted_at, :datetime
    add_index :capital_distributions, :deleted_at
    add_column :capital_distribution_payments, :deleted_at, :datetime
    add_index :capital_distribution_payments, :deleted_at
    
  end
end
