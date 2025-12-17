class CreateAiPortfolioReports < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_portfolio_reports do |t|
      t.integer :portfolio_company_id
      t.integer :analyst_id
      t.string :status
      t.date :report_date

      t.timestamps
    end
  end
end
