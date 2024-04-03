class SupportClientMapping < ApplicationRecord
  include Trackable.new
  belongs_to :user
  belongs_to :entity

  def to_s
    "#{user} - #{entity}"
  end

  # rubocop:disable Rails/SkipsModelValidations
  def self.disable_expired
    SupportClientMapping.where('enabled = ? and end_date < ?', true, Time.zone.today).update_all(enabled: false)
  end
  # rubocop:enable Rails/SkipsModelValidations
end
