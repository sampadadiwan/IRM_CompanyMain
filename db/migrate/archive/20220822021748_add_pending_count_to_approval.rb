class AddPendingCountToApproval < ActiveRecord::Migration[7.0]
  def change
    add_column :approvals, :pending_count, :integer, default: 0
  end
end
