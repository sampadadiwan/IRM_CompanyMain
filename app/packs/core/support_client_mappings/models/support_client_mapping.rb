class SupportClientMapping < ApplicationRecord
  include Trackable.new
  belongs_to :user
  belongs_to :entity

  def to_s
    "#{user} - #{entity}"
  end

  def self.disable_expired
    SupportClientMapping.where('enabled = ? and end_date < ?', true, Time.zone.today).update_all(enabled: false)
  end

  after_create :enable_support
  def enable_support
    entity.permissions.set(:enable_support)
    entity.save
    entity.employees.each do |user|
      user.update_column(:enable_support, true)
    end
  end
end
