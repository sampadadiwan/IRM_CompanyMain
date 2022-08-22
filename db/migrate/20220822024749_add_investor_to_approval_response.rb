class AddInvestorToApprovalResponse < ActiveRecord::Migration[7.0]
  def change
    add_reference :approval_responses, :investor, null: false, foreign_key: true
  end
end
