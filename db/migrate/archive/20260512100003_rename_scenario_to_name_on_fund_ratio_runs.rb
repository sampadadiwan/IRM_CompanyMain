# Renames fund_ratio_runs.scenario → fund_ratio_runs.name and populates it with the
# canonical fingerprint that encodes the computation inputs (fund IDs, portfolio company
# IDs, tags, sectors). The fingerprint is the primary lookup key used by the dashboard
# filter for exact-match queries. See docs/modules/funds/fund_ratios/fund_ratio_run.md — "fingerprint name".
class RenameScenarioToNameOnFundRatioRuns < ActiveRecord::Migration[7.2]
  def up
    rename_column :fund_ratio_runs, :scenario, :name

    # Backfill: overwrite whatever string was in the old scenario column with the
    # proper fingerprint. Uses the same logic as FundRatioRun.fingerprint so that
    # existing rows become queryable via for_filter without code changes.
    FundRatioRun.find_each do |run|
      run.update_columns(name: FundRatioRun.fingerprint(
        fund_ids:              run.fund_ids,
        portfolio_company_ids: run.portfolio_company_ids,
        tags:                  run.portfolio_companies_tags,
        sectors:               run.sectors
      ))
    end

    # Unique index: the same computation inputs on the same date for the same entity
    # must produce exactly one run — prevents duplicate results in the dashboard.
    add_index :fund_ratio_runs, %i[entity_id end_date name],
              unique: true,
              name:   "idx_frr_unique_fingerprint"

    change_column_null :fund_ratio_runs, :name, false
  end

  def down
    remove_index :fund_ratio_runs, name: "idx_frr_unique_fingerprint"
    change_column_null :fund_ratio_runs, :name, true
    rename_column :fund_ratio_runs, :name, :scenario
  end
end
