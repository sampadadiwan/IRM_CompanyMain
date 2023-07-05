class CreateAggregatePortfolioInvestments < ActiveRecord::Migration[7.0]
  def change
    create_table :aggregate_portfolio_investments do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :fund, null: false, foreign_key: true
      t.references :portfolio_company, null: false, foreign_key: {to_table: :investors}
      t.decimal :quantity, precision: 20, scale: 2, default: "0.0"
      t.decimal :fmv_cents, precision: 20, scale: 2, default: "0.0"
      t.decimal :avg_cost_cents, precision: 20, scale: 2, default: "0.0"

      t.timestamps
    end
  end
end
