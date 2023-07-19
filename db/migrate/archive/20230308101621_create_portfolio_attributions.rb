class CreatePortfolioAttributions < ActiveRecord::Migration[7.0]
  def change
    create_table :portfolio_attributions do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :fund, null: false, foreign_key: true
      t.references :sold_pi, null: false, foreign_key: {to_table: :portfolio_investments}
      t.references :bought_pi, null: false, foreign_key: {to_table: :portfolio_investments}
      t.decimal :quantity, precision: 20, scale: 8, default: "0.0"

      t.timestamps
    end
  end
end
