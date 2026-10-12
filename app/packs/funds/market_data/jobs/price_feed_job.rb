# Daily price feed: for every entity with Market prices and the price feed on, loads the closing
# price of each Market instrument from each selected provider (NSE, BSE, AMFI), then records
# corporate actions reported for its NSE tickers. Weekends skipped. Design card ②.
# Worked examples H8, H10, E42–E47, X15 — openspec/changes/fund-market-data/business-rules.md
class PriceFeedJob < ApplicationJob
  queue_as :low

  # nse_fo prices derivatives (DerivativeFeed), not instruments
  INSTRUMENT_PROVIDERS = %w[nse bse amfi].freeze

  def perform(run_date = nil)
    run_date = run_date.present? ? Date.parse(run_date.to_s) : Time.zone.today
    return if run_date.saturday? || run_date.sunday?

    Entity.where_permissions(:enable_market_prices).find_each do |entity|
      setting = MarketDataSetting.find_by(entity_id: entity.id, fund_id: nil)
      next unless setting&.price_feed_enabled

      (setting.price_providers & INSTRUMENT_PROVIDERS).each do |provider|
        MarketDataFeedRunner.call(entity:, kind: "prices", provider:, run_date:)
      end
      CorporateActionFeed.call(entity:, run_date:) if setting.price_providers.include?("nse")
      # Listed derivatives: NSE F&O settlement prices (H13)
      DerivativeFeed.call(entity:, run_date:) if setting.price_providers.include?("nse_fo") && entity.permissions.enable_derivatives?
    end
  end
end
