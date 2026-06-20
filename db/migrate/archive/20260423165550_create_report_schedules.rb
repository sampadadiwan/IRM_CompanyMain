class CreateReportSchedules < ActiveRecord::Migration[8.1]
  def change
    create_table :report_schedules do |t|
      t.references :report, null: false, foreign_key: true
      t.string :frequency, null: false
      t.text :recipients, null: false
      t.string :cron_expression
      t.boolean :active, default: true, null: false
      t.datetime :last_run_at

      t.timestamps
    end
  end
end
