class OptionalUserForApprovalResponse < ActiveRecord::Migration[7.0]
  def change
    change_column_null :approval_responses, :response_user_id, true
  end
end
