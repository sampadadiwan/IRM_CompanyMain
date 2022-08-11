class InvestmentSnapshotJob < ApplicationJob
  queue_as :default

  # This is called on the 1st of every month by cron
  def perform
    Entity.where("snapshot_frequency_months > 0").each do |e|
      if e.last_snapshot_on + e.snapshot_frequency_months.months <= Time.zone.today
        Rails.logger.debug do
          "Processing snapshot for #{e.name}, last_snapshot_on #{e.last_snapshot_on} snapshot_frequency_months #{e.snapshot_frequency_months}"
        end

        e.investments.each do |i|
          s = InvestmentSnapshot.new(i.attributes.except("aggregate_investment_id", "id"))
          s.as_of = Time.zone.today
          s.investment = i
          s.save!
        end

        e.last_snapshot_on = Time.zone.today
        e.save
      else
        Rails.logger.debug do
          "Skipping snapshot for #{e.name}, last_snapshot_on #{e.last_snapshot_on} snapshot_frequency_months #{e.snapshot_frequency_months}"
        end
      end
    end

    nil
  end
end
