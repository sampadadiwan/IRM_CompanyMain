class CreateFees < ActiveRecord::Migration[7.0]
  def change
    create_table :fees do |t|
      t.string :advisor_name, limit: 30
      t.decimal :amount_cents, precision: 10, scale: 2, default: "0.0"
      t.string :amount_label, limit: 10
      t.references :owner, null: false, polymorphic: true
      t.references :entity, null: false, foreign_key: true

      t.timestamps
    end
  end
end
