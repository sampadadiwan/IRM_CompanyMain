class CreateExchangeRates < ActiveRecord::Migration[7.0]
  def change
    create_table :exchange_rates do |t|
      t.references :entity, null: false, foreign_key: true
      t.string :from, limit: 5
      t.string :to, limit: 5
      t.decimal :rate, :decimal, precision: 20, scale: 8, default: "0.0"
      t.boolean :latest, default: true
      t.timestamps
    end
  end
end
