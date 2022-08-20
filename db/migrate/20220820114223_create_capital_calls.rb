class CreateCapitalCalls < ActiveRecord::Migration[7.0]
  def change
    create_table :capital_calls do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :fund, null: false, foreign_key: true
      t.string :name
      t.decimal :percentage_called, precision: 5, scale: 2, default: "0.0"
      t.decimal :collected_amount_cents, precision: 20, scale: 2, default: "0.0"
      t.decimal :due_amount_cents, precision: 20, scale: 2, default: "0.0"      
      t.date :due_date
      t.text :notes

      t.timestamps
    end
  end
end
