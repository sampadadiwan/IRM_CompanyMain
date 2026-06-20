# Prepares fund_ratios to participate in the FundRatioRun system:
#   1. Makes fund_id nullable — cross-fund and cross-portfolio rows no longer carry a
#      meaningful fund_id; the computation context lives on FundRatioRun instead.
#   2. Adds fund_ratio_run_id FK so each ratio can point back to the run that created it.
#
# Historical rows (created before this migration) keep their fund_id and have
# fund_ratio_run_id = NULL. They continue to work as before.
#
# See docs/features/fund_ratio_run.md
class UpdateFundRatiosForRuns < ActiveRecord::Migration[7.2]
  def up
    # MySQL requires dropping the FK constraint before changing column nullability.
    remove_foreign_key :fund_ratios, :funds
    change_column_null :fund_ratios, :fund_id, true   # allow NULL for cross-run rows
    add_foreign_key    :fund_ratios, :funds, column: :fund_id

    add_reference :fund_ratios, :fund_ratio_run, null: true, foreign_key: true
  end

  def down
    remove_reference :fund_ratios, :fund_ratio_run, foreign_key: true

    # WARNING: rolling back will fail if any cross-run rows exist with fund_id NULL.
    # Clean those up manually before running db:rollback.
    remove_foreign_key :fund_ratios, :funds
    change_column_null :fund_ratios, :fund_id, false
    add_foreign_key    :fund_ratios, :funds, column: :fund_id
  end
end
