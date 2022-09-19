class AddHoldingToShareTransfer < ActiveRecord::Migration[7.0]
  def change
    add_reference :share_transfers, :from_holding, null: true, foreign_key: { to_table: :holdings }
    add_reference :share_transfers, :to_holding, null: true, foreign_key: { to_table: :holdings }
    change_column :share_transfers, :to_investment_id, :bigint, null: true
    change_column :share_transfers, :to_investor_id, :bigint, null: true
    remove_column :share_transfers, :to_user_id, :bigint, null: true
    remove_column :share_transfers, :from_user_id, :bigint, null: true
  end
end
