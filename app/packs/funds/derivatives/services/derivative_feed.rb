# Values the entity's open listed contracts from the NSE F&O settlement price: value = settlement
# price × open lots × lot size (negative for a short), recorded as a Market valuation event (one per
# contract and date — a re-run is harmless). Worked example H13 — fund-market-data.
class DerivativeFeed
  def self.call(entity:, run_date:)
    contracts = DerivativeContract.where(entity_id: entity.id, status: "open", listed: true, exchange: "NSE")
                                  .where.not(feed_symbol: [nil, ""]).to_a
    return if contracts.empty?

    quotes = NseFoProvider.new.fetch(contracts.map(&:feed_symbol).uniq, run_date)
    contracts.each do |contract|
      quote = quotes[contract.feed_symbol]
      next unless quote&.value&.positive?

      value = quote.value * contract.open_lots.to_d * contract.lot_size.to_d * 100
      value = -value unless contract.long?
      DerivativeEventRecorder.call(contract:, idempotency_key: "nse_fo:#{contract.id}:#{run_date.iso8601}",
                                   params: { event_type: "valuation", event_date: run_date, value_cents: value.round(2),
                                             source: "market", provider: quote.label })
    end
  rescue MarketDataProvider::Error => e
    Rails.logger.warn { "DerivativeFeed entity=#{entity.id}: #{e.message}" }
  end
end
