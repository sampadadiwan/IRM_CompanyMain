class AddSignatureTypeToFund < ActiveRecord::Migration[7.0]
  def change
    add_column :funds, :fund_signature_types, :string, limit: 20
    add_column :funds, :investor_signature_types, :string, limit: 20
    add_column :capital_commitments, :investor_signature_types, :string, limit: 20
  end
end
