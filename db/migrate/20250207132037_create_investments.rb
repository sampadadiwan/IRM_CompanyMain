class CreateInvestments < ActiveRecord::Migration[7.2]
  def change
    create_table :investments do |t|
      t.references :portfolio_company, null: false, foreign_key: { to_table: :investors } 
      t.references :entity, null: false
      t.string :category, limit: 10
      t.string :currency, limit: 3
      t.string :investor_name
      t.string :investment_type, limit: 15
      t.string :funding_round, limit: 40
      t.decimal :quantity
      t.decimal :price_cents, precision: 20, scale: 2, default: 0.0
      t.decimal :amount_cents, precision: 20, scale: 2, default: 0.0
      t.date :investment_date
      t.text :notes

      t.timestamps
    end
  end
end
