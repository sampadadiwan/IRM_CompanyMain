# Allocation Run Checker — see docs/modules/allocation/allocation_run_checker_requirements.md.
#
# One report per AllocationRun, holding the Pass / Warn / Fail result of the deterministic
# checks in sections 1 (did the run happen correctly) and 2 (do the numbers add up). The
# individual findings live in json_fields rather than their own table: they are only ever
# read back as a whole report, never queried across runs, and a run with thousands of
# outlier folios must not put thousands of rows into a table nobody indexes.
class CreateAllocationRunReports < ActiveRecord::Migration[8.1]
  def change
    create_table :allocation_run_reports do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :fund, null: false, foreign_key: true
      # The person who asked for the check, not the person who ran the allocation.
      t.references :user, null: false, foreign_key: true
      # One report per run: re-checking a run overwrites its report rather than accumulating
      # history, so the row on the allocation screen always has exactly one badge to show.
      t.references :allocation_run, null: false, foreign_key: true,
                   index: { unique: true, name: "idx_allocation_run_reports_unique_run" }
      # Pending -> Pass | Warn | Fail | Error
      t.string :status, limit: 10, null: false, default: "Pending"
      # { "findings" => [...], "duration_ms" => 123 } — see AllocationRunReportBuild::Finding.
      t.json :json_fields
      t.text :message
      t.datetime :checked_at
      t.timestamps
    end
  end
end
