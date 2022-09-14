class AddDateToApproval < ActiveRecord::Migration[7.0]
  def change
    add_column :approvals, :due_date, :date
  end
end
