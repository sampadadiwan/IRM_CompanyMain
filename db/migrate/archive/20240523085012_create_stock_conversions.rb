class CreateStockConversions < ActiveRecord::Migration[7.1]
  def change
    create_table :stock_conversions do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :from_portfolio_investment, null: false, foreign_key: { to_table: :portfolio_investments }
      t.references :fund, null: false, foreign_key: true
      t.references :from_instrument, null: false, foreign_key: { to_table: :investment_instruments }
      t.decimal :from_quantity,precision: 20, scale: 2
      t.references :to_instrument, null: false, foreign_key: { to_table: :investment_instruments }
      t.decimal :to_quantity, precision: 20, scale: 2
      t.references :to_portfolio_investment, null: true, foreign_key: { to_table: :portfolio_investments }
      t.text :notes 

      t.timestamps
    end
  end
end
