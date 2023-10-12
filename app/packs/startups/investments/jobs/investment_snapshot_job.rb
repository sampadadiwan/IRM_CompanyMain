class InvestmentSnapshotJob < ApplicationJob
  queue_as :low

  # This is called on the 1st of every month by cron
  def perform
    Chewy.strategy(:sidekiq) do
      Entity.joins(:entity_setting).where("entity_setting.snapshot_frequency_months > 0").find_each do |e|
        next unless e.entity_setting.last_snapshot_on + e.entity_setting.snapshot_frequency_months.months <= Time.zone.today

        Rails.logger.debug do
          "Processing snapshot for #{e.name}, last_snapshot_on #{e.entity_setting.last_snapshot_on} snapshot_frequency_months #{e.entity_setting.snapshot_frequency_months}"
        end

        e.investments.each do |i|
          s = InvestmentSnapshot.new(i.attributes.except("aggregate_investment_id", "id"))
          s.as_of = Time.zone.today
          s.investment = i
          s.save!
        end

        e.last_snapshot_on = Time.zone.today
        e.save
      end
    end
  end
end
