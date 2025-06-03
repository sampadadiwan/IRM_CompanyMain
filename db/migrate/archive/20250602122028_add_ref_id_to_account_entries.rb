class AddRefIdToAccountEntries < ActiveRecord::Migration[8.0]
  def up
    # Add the column with default 0 and NOT NULL constraint
    add_column :account_entries, :ref_id, :integer, default: 0, null: false

    # Remove the old unique index
    remove_index :account_entries, name: "index_accounts_on_unique_fields"

    # Add the new unique index with ref_id included
    add_index :account_entries,
              [:name, :fund_id, :capital_commitment_id, :entry_type, :reporting_date, :cumulative, :deleted_at, :parent_type, :parent_id, :ref_id, :amount_cents],
              unique: true,
              name: "index_accounts_on_unique_fields"
  end

  def down
    # Remove the new unique index
    remove_index :account_entries, name: "index_accounts_on_unique_fields"

    # Add the old unique index back without ref_id
    add_index :account_entries,
              [:name, :fund_id, :capital_commitment_id, :entry_type, :reporting_date, :cumulative, :deleted_at, :parent_type, :parent_id],
              unique: true,
              name: "index_accounts_on_unique_fields"

    # Remove the ref_id column
    remove_column :account_entries, :ref_id
  end
end
