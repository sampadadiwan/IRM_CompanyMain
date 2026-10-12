# Every exchange rate records where it came from (source / provider / rate type), may belong to one
# fund (fund-specific rates), and — for derived rates — links to the two rates it was built from.
# Existing rates become entity-wide Manual rates, so every conversion resolves exactly as before.
#
# Uniqueness stays in the model (ExchangeRateShared validates as_of per pair, source and owner):
# production already holds a few duplicate (entity, pair, date) rows, so a DB unique key cannot be
# added without deleting data. The index below is non-unique and serves the resolver's lookups.
# Safe to re-run on MySQL, where a failed run leaves the columns behind (DDL isn't transactional).
# Worked examples E16, H21 — openspec/changes/fund-market-data/business-rules.md
class AddSourcesToExchangeRates < ActiveRecord::Migration[8.1]
  COLUMNS = {
    source: [:string, { limit: 10, null: false, default: "manual" }],
    provider: [:string, { limit: 40 }],
    rate_type: [:string, { limit: 10, null: false, default: "reference" }],
    owner_type: [:string, { limit: 20 }],
    owner_id: [:bigint, {}],
    leg1_id: [:bigint, {}],
    leg2_id: [:bigint, {}]
  }.freeze

  def up
    missing = COLUMNS.reject { |name, _| column_exists?(:exchange_rates, name) }
    if missing.any?
      change_table :exchange_rates, bulk: true do |t|
        missing.each { |name, (type, opts)| t.column name, type, **opts }
      end
    end

    # Provider for existing rows: uploaded or typed by a user
    execute "UPDATE exchange_rates SET provider = CASE WHEN import_upload_id IS NULL THEN 'User' ELSE 'Upload' END WHERE provider IS NULL"

    add_index :exchange_rates, %i[entity_id owner_type owner_id from to as_of source], name: "idx_exchange_rates_source" unless index_exists?(:exchange_rates, nil, name: "idx_exchange_rates_source")
    add_index :exchange_rates, %i[owner_type owner_id from to as_of], name: "idx_exchange_rates_owner" unless index_exists?(:exchange_rates, nil, name: "idx_exchange_rates_owner")
    add_index :exchange_rates, :leg1_id unless index_exists?(:exchange_rates, :leg1_id)
    add_index :exchange_rates, :leg2_id unless index_exists?(:exchange_rates, :leg2_id)
  end

  def down
    change_table :exchange_rates, bulk: true do |t|
      t.remove_index name: "idx_exchange_rates_source", if_exists: true
      t.remove_index name: "idx_exchange_rates_owner", if_exists: true
      t.remove_index :leg1_id, if_exists: true
      t.remove_index :leg2_id, if_exists: true
      t.remove(*COLUMNS.keys.select { |name| column_exists?(:exchange_rates, name) })
    end
  end
end
