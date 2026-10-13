# Market Data › Run history: the entity's feed runs, newest first. E11, E14, X6 — fund-market-data.
module MarketData
  class RunsController < ApplicationController
    def index
      setting = MarketDataSetting.for_entity(current_user.entity)
      authorize(setting, :show?)
      @bread_crumbs = { 'Market Data': market_data_settings_path, 'Run history': nil }
      # Runs have no policy of their own: access is the setting's show? above, rows are the user's entity only
      skip_policy_scope
      @runs = MarketDataRun.where(entity_id: current_user.entity_id).recent_first.limit(200)
    end
  end
end
