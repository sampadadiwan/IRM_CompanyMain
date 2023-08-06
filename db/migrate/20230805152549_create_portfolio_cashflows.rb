class CreatePortfolioCashflows < ActiveRecord::Migration[7.0]
  def change
    create_table :portfolio_cashflows do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :fund, null: false, foreign_key: true
      t.references :portfolio_company, null: false, foreign_key: {to_table: :investors}
      t.references :aggregate_portfolio_investment, null: false, foreign_key: true
      t.date :payment_date
      t.decimal :amount_cents, precision: 20, scale: 2, default: "0.0"
      t.text :notes

      t.timestamps
    end
  end
end
