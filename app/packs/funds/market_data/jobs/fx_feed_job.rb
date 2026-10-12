# Daily FX rate feed: for every entity with Market FX rates and the FX feed switched on, loads that
# day's rates from each selected provider. Weekends are skipped silently (E13 — no run row, no
# email). openspec/changes/fund-market-data — design card ②.
class FxFeedJob < ApplicationJob
  queue_as :low

  def perform(run_date = nil)
    run_date = run_date.present? ? Date.parse(run_date.to_s) : Time.zone.today
    # E13 — Edge case: weekend skipped
    return if run_date.saturday? || run_date.sunday?

    Entity.where_permissions(:enable_market_rates).find_each do |entity|
      setting = MarketDataSetting.find_by(entity_id: entity.id, fund_id: nil)
      next unless setting&.fx_feed_enabled

      setting.fx_providers.each do |provider|
        MarketDataFeedRunner.call(entity:, kind: "fx", provider:, run_date:)
      end
    end
  end
end
