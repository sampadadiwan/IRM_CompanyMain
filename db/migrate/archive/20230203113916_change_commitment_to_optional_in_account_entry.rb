class ChangeCommitmentToOptionalInAccountEntry < ActiveRecord::Migration[7.0]
  def change
    change_column :account_entries, :capital_commitment_id, :bigint, null: true
    change_column :account_entries, :investor_id, :bigint, null: true
  end
end
