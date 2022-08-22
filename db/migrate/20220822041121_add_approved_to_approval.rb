class AddApprovedToApproval < ActiveRecord::Migration[7.0]
  def change
    add_column :approvals, :approved, :boolean, default: false
  end
end
