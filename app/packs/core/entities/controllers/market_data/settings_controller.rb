# Entity › Settings › Market Data: feeds, cross-rate pivot, new-fund defaults and NAV limits.
# openspec/changes/fund-market-data — design card ① (H2, E9, X2, X4, X5).
module MarketData
  class SettingsController < ApplicationController
    before_action :set_setting

    def show
      @bread_crumbs = { 'Market Data': market_data_settings_path }
    end

    def update
      @setting.assign_attributes(setting_params)
      if @setting.save
        redirect_to market_data_settings_path, notice: "Market Data settings saved."
      else
        @bread_crumbs = { 'Market Data': market_data_settings_path }
        render :show, status: :unprocessable_entity
      end
    end

    # Test feed: fetches from every selected provider without storing anything and lists what was
    # found (E45 — Edge case: test feed). Shown on the settings page.
    def test_feed
      run_date = MarketDataFeedRunner.latest_weekday
      providers = (@setting.fx_feed_enabled ? @setting.fx_providers.map { |p| ["fx", p] } : []) +
                  (@setting.price_feed_enabled ? (@setting.price_providers & PriceFeedJob::INSTRUMENT_PROVIDERS).map { |p| ["prices", p] } : [])
      @test_results = providers.map do |kind, provider|
        MarketDataFeedRunner.call(entity: @setting.entity, kind:, provider:, run_date:, dry_run: true)
      end
      @bread_crumbs = { 'Market Data': market_data_settings_path }
      render :show
    end

    private

    # The entity's row (built with defaults the first time), authorized per action
    def set_setting
      @setting = MarketDataSetting.for_entity(current_user.entity)
      authorize(@setting, { "show" => :show?, "test_feed" => :test_feed? }.fetch(action_name, :update?))
    end

    def setting_params
      params.require(:market_data_setting).permit(
        :fx_feed_enabled, :price_feed_enabled, :pivot_currency,
        :max_rate_age_days, :max_price_age_days, :price_move_threshold_pct,
        fx_providers: [], price_providers: [], fund_defaults: FundEnabled::MARKET_DATA_FLAGS.keys
      )
    end
  end
end
