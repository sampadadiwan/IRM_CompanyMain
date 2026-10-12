# One row per evergreen notification sent for a record (per day for the daily checks), so a re-run
# of the daily job or a repeated callback never sends the same notification twice.
# open-ended-funds § Notifications
class EvergreenNotificationLog < ApplicationRecord
  belongs_to :entity
  belongs_to :fund

  # Runs the block only the first time this (key, record, day) is seen. The unique index settles races.
  def self.once(fund, key, record, on: Time.zone.today)
    begin
      create!(entity_id: fund.entity_id, fund_id: fund.id, key: key.to_s, record_type: record.class.name, record_id: record.id, sent_on: on)
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      return false # already sent
    end
    begin
      yield
    rescue StandardError
      # Not sent — let the next run try again (and let the caller see the real error)
      where(key: key.to_s, record_type: record.class.name, record_id: record.id, sent_on: on).delete_all
      raise
    end
    true
  end
end
