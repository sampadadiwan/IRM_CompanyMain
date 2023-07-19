class ChangeApprovalResponseStatus < ActiveRecord::Migration[7.0]
  def change
    change_column :approval_responses, :status, :string, limit: 50
  end
end
