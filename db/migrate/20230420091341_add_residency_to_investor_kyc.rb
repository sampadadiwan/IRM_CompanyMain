class AddResidencyToInvestorKyc < ActiveRecord::Migration[7.0]
  def change
    add_column :investor_kycs, :residency, :string, null: true, limit: 10
  end
end
