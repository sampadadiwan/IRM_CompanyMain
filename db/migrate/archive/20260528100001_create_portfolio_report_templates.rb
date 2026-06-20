class CreatePortfolioReportTemplates < ActiveRecord::Migration[7.2]
  def change
    create_table :portfolio_report_templates do |t|
      t.references :portfolio_report, null: false, foreign_key: true
      t.string     :name,          null: false
      t.string     :output_format, null: false                  # word | ppt
      t.json       :branding                                    # logo, primary_color, font fallbacks
      t.json       :section_order                              # ordered array of portfolio_report_section ids
      t.json       :kpi_layout                                  # categories, tags, n_periods, side_by_side
      t.bigint     :style_document_id                          # uploaded .docx or .pptx — styles only
      t.timestamps
    end

    add_index :portfolio_report_templates, :style_document_id
    add_foreign_key :portfolio_report_templates, :documents, column: :style_document_id
  end
end
