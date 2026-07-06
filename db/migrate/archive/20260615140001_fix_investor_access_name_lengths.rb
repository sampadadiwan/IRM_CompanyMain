class FixInvestorAccessNameLengths < ActiveRecord::Migration[7.1]
  def change
    # Match the users table which has no explicit limit (255) on first_name/last_name
    change_column :investor_accesses, :first_name, :string, limit: 255
    change_column :investor_accesses, :last_name, :string, limit: 255
  end
end
