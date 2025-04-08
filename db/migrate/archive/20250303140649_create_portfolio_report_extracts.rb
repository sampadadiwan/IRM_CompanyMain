class CreatePortfolioReportExtracts < ActiveRecord::Migration[7.2]
  def change
    create_table :portfolio_report_extracts do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :portfolio_report, null: false, foreign_key: true
      t.references :portfolio_report_section, null: false, foreign_key: true
      t.references :portfolio_company, null: false, foreign_key: { to_table: :investors } 
      t.date :start_date
      t.date :end_date
      t.json :data

      t.timestamps
    end
  end
end
