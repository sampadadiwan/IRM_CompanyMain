class AddResponseEnabledEmailTpApproval < ActiveRecord::Migration[7.1]
  def change
    add_column :approvals, :response_enabled_email, :boolean, default: false, null: false
  end
end
