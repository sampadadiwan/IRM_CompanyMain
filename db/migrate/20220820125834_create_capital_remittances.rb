class CreateCapitalRemittances < ActiveRecord::Migration[7.0]
  def change
    create_table :capital_remittances do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :fund, null: false, foreign_key: true
      t.references :capital_call, null: false, foreign_key: true
      t.references :investor, null: false, foreign_key: true
      t.string :status, limit: 10
      t.decimal :due_amount_cents, precision: 20, scale: 2, default: "0.0"    
      t.decimal :collected_amount_cents, precision: 20, scale: 2, default: "0.0"    
      t.text :notes

      t.timestamps
    end
  end
end
