# Fund feature switches as one bitflag column (FundEnabled), like entities.permissions.
# Backfills the six boolean columns into bits 0..5 (same order as FundEnabled::LEGACY_FLAGS).
# The boolean columns stay (unused) for one release and are dropped by a follow-up change.
# Worked example E4 — openspec/changes/fund-market-data/business-rules.md
class AddFeaturesToFunds < ActiveRecord::Migration[8.1]
  def up
    add_column :funds, :features, :bigint, null: false, default: 0

    # One statement, portable across MySQL and SQLite: each boolean contributes its bit
    execute <<~SQL.squish
      UPDATE funds SET features =
        (CASE WHEN show_fund_ratios = 1 THEN 1 ELSE 0 END) +
        (CASE WHEN show_fund_units = 1 THEN 2 ELSE 0 END) +
        (CASE WHEN show_portfolios = 1 THEN 4 ELSE 0 END) +
        (CASE WHEN show_valuations = 1 THEN 8 ELSE 0 END) +
        (CASE WHEN enable_ai_commentary = 1 THEN 16 ELSE 0 END) +
        (CASE WHEN editable_formulas = 1 THEN 32 ELSE 0 END)
    SQL
  end

  def down
    remove_column :funds, :features
  end
end
