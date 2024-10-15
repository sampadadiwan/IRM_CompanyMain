class CreateAllocations < ActiveRecord::Migration[7.1]
  def change
    create_table :allocations do |t|
      t.references :offer, null: false, foreign_key: true
      t.references :interest, null: false, foreign_key: true
      t.references :secondary_sale, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      t.decimal :quantity, precision: 10, scale: 2, default: 0
      t.decimal :avail_offer_quantity, precision: 10, scale: 2, default: 0
      t.decimal :avail_interest_quantity, precision: 10, scale: 2, default: 0
      t.decimal :amount_cents, precision: 20, scale: 2, default: 0
      t.text :notes
      t.boolean :verified, default: false
      t.references :document_folder, null: true, foreign_key: {to_table: :folders}

      t.timestamps
    end

    add_column :offers, :price, :decimal, precision: 20, scale: 2, default: 0
  end
end
