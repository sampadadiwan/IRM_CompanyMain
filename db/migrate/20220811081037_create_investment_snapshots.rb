class CreateInvestmentSnapshots < ActiveRecord::Migration[7.0]
  def change
    create_table :investment_snapshots do |t|
      t.string :investment_type, limit: 100
      t.references :investor, null: false, foreign_key: true
      t.string :investor_type, limit: 100
      t.references :entity, null: false, foreign_key: true
      t.string :status, limit: 20
      t.string :investment_instrument, limit: 100
      t.integer :quantity
      t.decimal :initial_value
      t.decimal :current_value
      t.string :category, limit: 100
      t.datetime :deleted_at
      t.decimal :percentage_holding
      t.boolean :employee_holdings
      t.integer :diluted_quantity
      t.decimal :diluted_percentage
      t.string :currency, limit: 10
      t.string :units, limit: 15
      t.decimal :amount_cents
      t.decimal :price_cents
      t.references :funding_round, null: false, foreign_key: true
      t.decimal :liquidation_preference
      t.string :spv, limit: 50
      t.date :investment_date
      t.string :liq_pref_type, limit: 25
      t.string :anti_dilution, limit: 50
      t.date :as_of
      t.string :tag, limit: 10
      t.references :investment, null: false, foreign_key: true

      t.timestamps
    end
  end
end
