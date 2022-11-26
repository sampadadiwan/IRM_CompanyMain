class AddSignatoriesToFund < ActiveRecord::Migration[7.0]
  def change
    add_reference :funds, :fund_signatory,  null: true, foreign_key: { to_table: :users }
    add_reference :funds, :trustee_signatory,  null: true, foreign_key: { to_table: :users }
    add_reference :capital_commitments, :investor_signatory, null: true, foreign_key: { to_table: :users }
  end
end
