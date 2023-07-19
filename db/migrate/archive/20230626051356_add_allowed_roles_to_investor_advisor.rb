class AddAllowedRolesToInvestorAdvisor < ActiveRecord::Migration[7.0]
  def change
    add_column :investor_advisors, :allowed_roles, :string, limit: 100
  end
end
