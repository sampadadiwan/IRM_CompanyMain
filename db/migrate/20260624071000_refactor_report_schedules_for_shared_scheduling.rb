class RefactorReportSchedulesForSharedScheduling < ActiveRecord::Migration[8.1]
  def change
    rename_column :report_schedules, :active, :enabled

    add_column :report_schedules, :next_run_at, :datetime
    add_column :report_schedules, :run_on_day, :integer
    add_column :report_schedules, :run_at_time, :time, null: false, default: "09:00:00"
    add_column :report_schedules, :timezone, :string, limit: 50, null: false, default: "UTC"

    # Preserve the previous hardcoded "9 AM, Monday for weekly, 1st for monthly" semantics
    # that cron_expression used to encode but ReportBuilderSchedulerJob never actually read.
    reversible do |dir|
      dir.up { execute "UPDATE report_schedules SET run_on_day = 1" }
    end

    remove_column :report_schedules, :cron_expression, :string

    add_index :report_schedules, %i[next_run_at enabled], name: "idx_report_schedules_polling"
  end
end
