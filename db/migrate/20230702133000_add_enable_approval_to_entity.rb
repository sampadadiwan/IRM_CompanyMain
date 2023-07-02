class AddEnableApprovalToEntity < ActiveRecord::Migration[7.0]
  def change
    add_column :entities, :enable_approvals, :boolean, default: false
    Entity.update_all(enable_approvals: true)
    User.permissions.set_all!(:enable_approvals)
  end
end
