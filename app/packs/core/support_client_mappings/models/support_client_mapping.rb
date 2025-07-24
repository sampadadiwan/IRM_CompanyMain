class SupportClientMapping < ApplicationRecord
  include Trackable.new

  belongs_to :user
  belongs_to :entity

  def to_s
    "#{user} - #{entity}"
  end

  def self.disable_expired
    SupportClientMapping.where('enabled = ? and end_date < ?', true, Time.zone.today).find_each(&:disable_support)
  end

  after_commit :enable_disable
  def enable_disable
    if enabled
      enable_support
    else
      disable_support
    end
  end

  def enable_support
    update_column(:enabled, true)
    entity.permissions.set(:enable_support)
    entity.save
    entity.employees.each do |user|
      user.update_column(:enable_support, true)
    end
  end

  def disable_support
    update_column(:enabled, false)
    entity.permissions.unset(:enable_support)
    entity.save
    entity.employees.each do |user|
      user.update_column(:enable_support, false)
    end
  end
end
