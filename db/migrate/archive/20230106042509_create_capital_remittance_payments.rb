class CreateCapitalRemittancePayments < ActiveRecord::Migration[7.0]
  def change
    create_table :capital_remittance_payments do |t|
      t.references :fund, null: false, foreign_key: true
      t.references :capital_remittance, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      t.decimal :amount_cents, precision: 20, scale: 2, default: "0.0"
      t.date :payment_date
      t.text :properties
      t.text :payment_proof_data 
      t.text :notes
      t.timestamps
    end
  end
end
