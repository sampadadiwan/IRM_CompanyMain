class AddTypeToAccountEntry < ActiveRecord::Migration[7.0]
  def change
    add_column :account_entries, :commitment_type, :string, limit: 10, default: "Pool"
  end
end
