class CreateExcusedInvestors < ActiveRecord::Migration[7.2]
  def change
    create_table :excused_investors do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :fund, null: false, foreign_key: true
      t.references :capital_commitment, null: false, foreign_key: true
      t.references :portfolio_company, null: true, foreign_key: { to_table: :investors } 
      t.references :aggregate_portfolio_investment, null: true, foreign_key: true
      t.references :portfolio_investment, null: true, foreign_key: true
      t.string :notes

      t.timestamps
    end
  end
end
