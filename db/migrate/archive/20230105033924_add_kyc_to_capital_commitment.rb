class AddKycToCapitalCommitment < ActiveRecord::Migration[7.0]
  def change
    add_reference :capital_commitments, :investor_kyc, null: true, foreign_key: true
  end
end
