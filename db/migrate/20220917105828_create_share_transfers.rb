class CreateShareTransfers < ActiveRecord::Migration[7.0]
  def change
    create_table :share_transfers do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :from_investor, null: true, foreign_key: { to_table: :investors }
      t.references :from_user, null: true, foreign_key: { to_table: :users }
      t.references :from_investment, null: true, foreign_key: { to_table: :investments }
      t.references :to_investor, null: false, foreign_key: { to_table: :investors }
      t.references :to_user, null: true, foreign_key: { to_table: :users }
      t.references :to_investment, null: false, foreign_key: { to_table: :investments }
      t.integer :quantity
      t.decimal :price, precision: 20, scale: 2, default: "0.0" 
      t.date :transfer_date
      t.references :transfered_by, null: false, foreign_key: { to_table: :users }

      t.timestamps
    end
  end
end
