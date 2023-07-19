class AddPermissionsToInvestorAdvisor < ActiveRecord::Migration[7.0]
  def change
    add_column :investor_advisors, :permissions, :integer, null: false, default: 0, limit: 8
  end
end
