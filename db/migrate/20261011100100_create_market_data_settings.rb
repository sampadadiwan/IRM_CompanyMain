# Entity Market Data settings (feeds, pivot currency, new-fund defaults, NAV limits) and per-fund
# limit overrides. fund_id NULL = the entity row. openspec fund-market-data — design card ①.
class CreateMarketDataSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :market_data_settings do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :fund, null: true, foreign_key: true
      t.boolean :fx_feed_enabled, null: false, default: false
      t.json :fx_providers
      t.boolean :price_feed_enabled, null: false, default: false
      t.json :price_providers
      t.string :pivot_currency, limit: 5, null: false, default: "USD"
      t.json :fund_defaults
      t.integer :max_rate_age_days
      t.integer :max_price_age_days
      t.decimal :price_move_threshold_pct, precision: 5, scale: 2
      t.datetime :deleted_at
      t.timestamps

      # One entity row and one row per fund
      t.index %i[entity_id fund_id], unique: true
      t.index :deleted_at
    end
  end
end
