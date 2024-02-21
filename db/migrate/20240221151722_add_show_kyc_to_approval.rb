class AddShowKycToApproval < ActiveRecord::Migration[7.1]
  def change
    add_column :approvals, :enable_approval_show_kycs, :boolean, default: false
  end
end
