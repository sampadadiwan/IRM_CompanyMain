class CreateFundUnitTransfers < ActiveRecord::Migration[8.0]
  def change
    create_table :fund_unit_transfers do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :fund, null: false, foreign_key: true
      t.references :from_commitment, null: false, foreign_key: { to_table: :capital_commitments }
      t.references :to_commitment, null: false, foreign_key: { to_table: :capital_commitments }
      t.integer :transfer_ratio
      t.date :transfer_date
      t.decimal :price, precision: 20, scale: 2
      t.decimal :premium, precision: 20, scale: 2
      t.boolean :transfer_account_entries
      t.string :account_entries_excluded
      t.string :transfer_token
      t.string :status
      t.timestamps
    end
  end
end
