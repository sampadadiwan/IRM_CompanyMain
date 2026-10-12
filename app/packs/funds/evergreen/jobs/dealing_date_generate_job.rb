# Daily: creates the next year's dealing dates for every evergreen fund from its calendars, so
# upcoming dates (and their journeys) exist before any order arrives. Idempotent: DealingDate.for
# finds existing dates. Registered in config/initializers/sidekiq.rb.
# Worked example H16 — openspec/changes/open-ended-funds/design.md#worked-examples
class DealingDateGenerateJob < ApplicationJob
  queue_as :low

  def perform(fund_id = nil)
    scope = EvergreenFundSetting.includes(fund: :entity)
    scope = scope.where(fund_id:) if fund_id
    scope.find_each do |setting|
      fund = setting.fund
      next unless fund.evergreen?

      DealingCalendar.all_dates(setting, from: Time.zone.today, to: Time.zone.today + 1.year).each { |date| DealingDate.for(fund, date) }
    rescue StandardError => e
      Rails.logger.error("[DealingDateGenerateJob] fund #{setting.fund_id}: #{e.class}: #{e.message}")
    end
  end
end
