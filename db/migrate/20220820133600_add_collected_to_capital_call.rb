class AddCollectedToCapitalCall < ActiveRecord::Migration[7.0]
  def change
    add_reference :capital_remittances, :capital_commitment, index: true
    add_foreign_key :capital_remittances, :capital_commitments
  end
end
