class AddTypeToShareTransfer < ActiveRecord::Migration[7.0]
  def change
    add_column :share_transfers, :transfer_type, :string, limit: 10
    add_column :share_transfers, :to_quantity, :integer, default: 0
  end
end
