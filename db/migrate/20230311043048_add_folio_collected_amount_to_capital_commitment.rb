class AddFolioCollectedAmountToCapitalCommitment < ActiveRecord::Migration[7.0]
  def change
    add_column :capital_commitments, :folio_collected_amount_cents, :decimal, precision: 20, scale: 2, default: 0
    add_column :capital_commitments, :folio_call_amount_cents, :decimal, precision: 20, scale: 2, default: 0
  end
end
