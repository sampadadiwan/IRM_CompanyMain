class AddFullNameToInvestorKyc < ActiveRecord::Migration[7.0]
  def change
    safety_assured { remove_column :investor_kycs, :first_name, :string }
    safety_assured { remove_column :investor_kycs, :middle_name, :string }
    safety_assured { remove_column :investor_kycs, :last_name, :string }
    add_column :investor_kycs, :full_name, :string, limit: 100
  end
end
