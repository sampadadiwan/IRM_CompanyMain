class CreatePortfolioReportDrafts < ActiveRecord::Migration[7.2]
  def change
    create_table :portfolio_report_drafts do |t|
      t.references :portfolio_company,          null: false, foreign_key: { to_table: :investors }
      t.references :portfolio_report,           null: false, foreign_key: true
      t.references :portfolio_report_template,  null: false, foreign_key: true
      t.references :user,                       null: false, foreign_key: true

      t.date    :start_date,               null: false
      t.date    :end_date,                 null: false
      t.string  :kpi_period_type,          null: false   # Month | Quarter | Half Year | Year | YTD
      t.string  :kpi_tag,                  null: false   # Actual | Budget | IC
      t.integer :n_periods,                null: false, default: 6

      t.json    :selected_kpi_mapping_ids  # array of InvestorKpiMapping ids chosen by user
      t.json    :kpi_table_data            # { metric_id => { period_label => value }, user_overrides: {} }
      t.json    :section_data              # { section_id => { llm_output: "...", user_edit: "..." } }

      t.string  :status, null: false, default: 'configuring'
      # configuring → generating → review → approved → exported

      t.bigint  :generated_document_id    # populated after export; draft is never deleted

      t.timestamps
    end

    add_index :portfolio_report_drafts, :generated_document_id
    add_index :portfolio_report_drafts, :status
    add_foreign_key :portfolio_report_drafts, :documents, column: :generated_document_id
  end
end
