# One row per entity, feed kind, provider and date: the feed's run log, the "Last run" on the
# Market Data card, and the send-once guard for the missing-data email (notified_at).
# Worked examples H4, E11, E14, X6, X7 — openspec/changes/fund-market-data/business-rules.md
class CreateMarketDataRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :market_data_runs do |t|
      t.references :entity, null: false, foreign_key: true
      t.string :kind, limit: 15, null: false
      t.string :provider, limit: 20, null: false
      t.date :run_date, null: false
      t.string :status, limit: 10, null: false, default: "running"
      t.integer :loaded_count, null: false, default: 0
      t.json :missing
      t.text :error_message
      t.datetime :notified_at
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps

      # A re-run for the same date updates the same row (E11)
      t.index %i[entity_id kind provider run_date], unique: true, name: "idx_market_data_runs_unique"
    end
  end
end
