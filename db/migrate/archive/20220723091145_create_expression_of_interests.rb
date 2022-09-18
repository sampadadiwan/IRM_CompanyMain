class CreateExpressionOfInterests < ActiveRecord::Migration[7.0]
  def change
    create_table :expression_of_interests do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :eoi_entity, null: false, foreign_key: {to_table: :entities}
      t.references :investment_opportunity, null: false, foreign_key: true
      t.decimal :amount_cents, precision: 15, scale: 2, default: "0.0"
      t.boolean :approved, default: false
      t.boolean :verified, default: false
      t.decimal :allocation_percentage, precision: 5, scale: 2, default: "0.0"
      t.decimal :allocation_amount_cents, precision: 15, scale: 2, default: "0.0"

      t.timestamps
    end
  end
end
