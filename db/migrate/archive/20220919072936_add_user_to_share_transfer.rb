class AddUserToShareTransfer < ActiveRecord::Migration[7.0]
  def change
    add_reference :share_transfers, :to_user, null: true, foreign_key: { to_table: :users }
    add_reference :share_transfers, :from_user, null: true, foreign_key: { to_table: :users }
    add_column :holdings, :preferred_conversion, :integer, default: 1
  end
end
