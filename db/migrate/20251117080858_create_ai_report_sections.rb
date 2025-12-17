class CreateAiReportSections < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_report_sections do |t|
      t.references :ai_portfolio_report, null: false, foreign_key: true
      t.string :section_type
      t.integer :order_index
      t.text :ai_generated_summary
      t.string :status

      t.timestamps
    end
  end
end
