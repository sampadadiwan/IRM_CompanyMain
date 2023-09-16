class AddExtendedPErmissionsToInvestorAdvisor < ActiveRecord::Migration[7.0]
  def change
    add_column :investor_advisors, :extended_permissions, :integer
  end
end
