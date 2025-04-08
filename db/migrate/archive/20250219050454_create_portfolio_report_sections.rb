class CreatePortfolioReportSections < ActiveRecord::Migration[7.2]
  def change
    create_table :portfolio_report_sections do |t|
      t.references :portfolio_report, null: false, foreign_key: true
      t.string :name, limit: 50
      t.text :data

      t.timestamps
    end
  end
end
