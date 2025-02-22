class CreatePortfolioReports < ActiveRecord::Migration[7.2]
  def change
    create_table :portfolio_reports do |t|
      t.references :entity, null: false, foreign_key: true
      t.string :name
      t.string :tags, limit: 100
      t.boolean :include_kpi, default: false
      t.boolean :include_portfolio_investments, default: false
      t.json :sections

      t.timestamps
    end
  end
end
