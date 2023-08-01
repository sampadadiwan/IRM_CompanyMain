class CreateScenarioInvestments < ActiveRecord::Migration[7.0]
  def change
    create_table :scenario_investments do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :fund, null: false, foreign_key: true
      t.references :portfolio_scenario, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.date :transaction_date
      t.references :portfolio_company, null: false, foreign_key: {to_table: :investors}
      t.decimal :price_cents, precision: 20, scale: 2, default: "0.0"
      t.decimal :quantity, precision: 20, scale: 2, default: "0.0"
      t.string :category, null: false, limit: 15
      t.string :sub_category, null: false, limit: 100
      t.text :notes

      t.timestamps
    end
  end
end
