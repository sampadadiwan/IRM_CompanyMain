class CreateInvestmentOpportunities < ActiveRecord::Migration[7.0]
  def change
    create_table :investment_opportunities do |t|
      t.references :entity, null: false, foreign_key: true
      t.string :company_name, limit: 100
      t.decimal :fund_raise_amount_cents, precision: 15, scale: 2, default: "0.0"
      t.decimal :valuation_cents, precision: 15, scale: 2, default: "0.0"
      t.decimal :min_ticket_size_cents, precision: 15, scale: 2, default: "0.0"
      t.date :last_date
      t.string :currency, limit: 10
      t.text :logo_data
      t.text :video_data
      

      t.timestamps
    end
  end
end
