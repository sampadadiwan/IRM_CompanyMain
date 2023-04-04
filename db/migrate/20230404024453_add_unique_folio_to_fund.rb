class AddUniqueFolioToFund < ActiveRecord::Migration[7.0]
  def change
    add_index :capital_commitments, [:fund_id, :folio_id, :deleted_at], unique: true
  end
end
