class CreatePortfolioInvestments < ActiveRecord::Migration[7.0]
  def change
    create_table :portfolio_investments do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :fund, null: false, foreign_key: true
      t.references :form_type, null: true, foreign_key: true
      t.references :portfolio_company, null: false, foreign_key: {to_table: :investors}
      t.string :portfolio_company_name, limit: 100
      t.date :investment_date
      t.decimal :amount_cents, precision: 20, scale: 2, default: "0.0"
      t.decimal :quantity, precision: 20, scale: 2, default: "0.0"
      t.string :investment_type, limit: 10
      t.text :notes
      t.text :properties

      t.timestamps
    end
  end
end
