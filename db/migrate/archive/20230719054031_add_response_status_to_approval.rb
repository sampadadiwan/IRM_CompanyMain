class AddResponseStatusToApproval < ActiveRecord::Migration[7.0]
  def change
    add_column :approvals, :response_status, :string
  end
end
