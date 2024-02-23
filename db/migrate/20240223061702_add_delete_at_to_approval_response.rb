class AddDeleteAtToApprovalResponse < ActiveRecord::Migration[7.1]
  def change
    add_column :approval_responses, :deleted_at, :timestamp
    add_index :approval_responses, :deleted_at
  end
end
