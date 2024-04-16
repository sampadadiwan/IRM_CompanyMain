class AddAutToInvestorKyc < ActiveRecord::Migration[7.1]
  def change
    add_column :investor_kycs, :agreement_unit_type, :string, limit: 20
  end
end
