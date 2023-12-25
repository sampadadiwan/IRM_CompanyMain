class CreateStockAdjustments < ActiveRecord::Migration[7.0]
  def change
    create_table :stock_adjustments do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :portfolio_company, null: false, foreign_key: {to_table: :investors}
      t.references :user, null: false, foreign_key: true
      t.decimal :adjustment, precision: 10, scale: 8, default: "0.0"
      t.text :notes

      t.timestamps
    end
  end
end
