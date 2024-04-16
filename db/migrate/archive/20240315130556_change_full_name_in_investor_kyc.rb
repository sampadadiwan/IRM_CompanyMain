class ChangeFullNameInInvestorKyc < ActiveRecord::Migration[7.1]
  def change
    change_column :investor_kycs, :full_name, :string, limit: 255
  end
end
