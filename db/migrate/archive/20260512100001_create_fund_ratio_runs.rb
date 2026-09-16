# Creates the fund_ratio_runs table, which stores one record per FundRatiosScenarioJob
# invocation. FundRatio rows reference this via fund_ratio_run_id so you can always
# trace which funds, companies, tags, and sectors fed a given set of results.
#
# Full design rationale: docs/modules/funds/fund_ratios/fund_ratio_run.md
class CreateFundRatioRuns < ActiveRecord::Migration[7.2]
  def up
    create_table :fund_ratio_runs do |t|
      t.references :entity,      null: false, foreign_key: true
      # anchor_fund is the fund the user launched the job from. Used only for document
      # folder resolution and policy scoping — nullable because it is not a calculation input.
      t.references :anchor_fund, null: true,  foreign_key: { to_table: :funds }
      t.references :user,        null: false, foreign_key: true
      t.string  :run_type,                  null: false  # "cross-fund" or "cross-portfolio"
      t.string  :scenario
      t.date    :end_date,                  null: false
      t.string  :currency
      # JSON arrays of bigint IDs — indexed below with multi-valued indexes.
      # No default: MySQL rejects literal defaults on JSON columns. Defaults are
      # enforced at the application layer via the attribute API in FundRatioRun.
      t.json    :fund_ids,                  null: false
      t.json    :portfolio_company_ids,     null: false
      t.json    :sectors,                   null: false
      # Raw tag string as submitted by the user (comma-separated).
      t.string  :portfolio_companies_tags
      t.timestamps
    end

    # Multi-valued indexes (MySQL 8.0.17+): each element of the JSON array gets its
    # own index entry, enabling efficient "? MEMBER OF (column)" queries without a
    # join table. See docs/modules/funds/fund_ratios/fund_ratio_run.md — "JSON Array Indexing".
    execute "ALTER TABLE fund_ratio_runs ADD INDEX idx_frr_fund_ids ((CAST(fund_ids AS UNSIGNED ARRAY)))"
    execute "ALTER TABLE fund_ratio_runs ADD INDEX idx_frr_portfolio_company_ids ((CAST(portfolio_company_ids AS UNSIGNED ARRAY)))"
  end

  def down
    drop_table :fund_ratio_runs
  end
end
