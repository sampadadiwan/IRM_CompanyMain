class AddStiTypeToInvestorKyc < ActiveRecord::Migration[7.1]
  def change
    add_column :investor_kycs, :type, :string, limit: 20
  end
end
