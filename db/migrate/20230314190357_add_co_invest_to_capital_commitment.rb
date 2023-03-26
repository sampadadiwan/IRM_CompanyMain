class AddCoInvestToCapitalCommitment < ActiveRecord::Migration[7.0]
  def change
    add_column :capital_commitments, :commitment_type, :string, limit: 10, default: "Pool"
    add_column :capital_calls, :commitment_type, :string, limit: 10, default: "Pool"
    CapitalCommitment.update_all(commitment_type: "Pool")
    CapitalCall.update_all(commitment_type: "Pool")
  end
end
