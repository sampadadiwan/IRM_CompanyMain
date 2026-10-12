# Instruments get identifiers and a pricing method; valuations record where a price came from.
# Existing instruments become Manual and existing valuations Manual, so fair values are unchanged.
# The ISIN in the SEBI custom field is copied into the new isin column.
# Worked examples E34, E36 — openspec/changes/fund-market-data/business-rules.md
class AddMarketPricingToInstrumentsAndValuations < ActiveRecord::Migration[8.1]
  class Instrument < ActiveRecord::Base
    self.table_name = "investment_instruments"
  end

  def up
    change_table :investment_instruments, bulk: true do |t|
      t.string :isin, limit: 12
      t.string :ticker, limit: 30
      t.string :exchange, limit: 10
      t.string :pricing_method, limit: 10, null: false, default: "manual"
      t.index %i[entity_id exchange ticker], unique: true, name: "idx_instruments_entity_exchange_ticker"
      t.index %i[entity_id isin], name: "idx_instruments_entity_isin"
    end

    change_table :valuations, bulk: true do |t|
      t.string :source, limit: 10, null: false, default: "manual"
      t.string :provider, limit: 40
      t.string :price_type, limit: 10, null: false, default: "close"
      t.remove_index name: "idx_latest_valuation"
      t.index %i[investment_instrument_id deleted_at synthetic source valuation_date], name: "idx_latest_valuation"
    end

    # E34 — copy the SEBI custom-field ISIN into the new column (small table)
    Instrument.reset_column_information
    Instrument.where.not(json_fields: nil).find_each do |instrument|
      fields = instrument.json_fields.is_a?(String) ? JSON.parse(instrument.json_fields) : instrument.json_fields
      isin = fields.to_h["sebi_isin"].to_s.strip.upcase
      instrument.update_columns(isin:) if isin.length == 12
    end
  end

  def down
    change_table :valuations, bulk: true do |t|
      t.remove_index name: "idx_latest_valuation"
      t.index %i[investment_instrument_id deleted_at synthetic valuation_date], name: "idx_latest_valuation"
      t.remove :source, :provider, :price_type
    end
    change_table :investment_instruments, bulk: true do |t|
      t.remove_index name: "idx_instruments_entity_exchange_ticker"
      t.remove_index name: "idx_instruments_entity_isin"
      t.remove :isin, :ticker, :exchange, :pricing_method
    end
  end
end
