class CreateReportInsights < ActiveRecord::Migration[8.0]
  def change
    unless table_exists? :report_insights
      create_table :report_insights do |t|
        t.references :report, null: false, foreign_key: true
        t.references :entity, null: false, foreign_key: true
        t.string :status
        t.text :ai_response
        t.text :status_message
        t.text :prompt_used
        t.text :notes
        t.json :charts_spec
        t.integer :record_count
        t.datetime :triggered_at
        t.string :trigger_type
        t.bigint :triggered_by_id
        t.timestamps
      end
    end
  end
end
