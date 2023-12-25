class AddLockedToApproval < ActiveRecord::Migration[7.1]
  def change
    add_column :approvals, :locked, :boolean
  end
end
