class UserAlert < ApplicationRecord
  belongs_to :user
  belongs_to :entity

  # The method is named `broadcast`, not `broadcast_ua` — this callback previously referenced
  # a method that doesn't exist, raising NoMethodError on any UserAlert.create!/save that
  # actually persists (e.g. ImportCapitalCommitment#warn_about_unsubscribed_investors). Most
  # other call sites never hit this: UserAlert.new(...).broadcast is called directly on an
  # unsaved record and never triggers an after_save_commit callback at all.
  after_save_commit :broadcast, on: %i[create update]
  validates :level, length: { maximum: 8 }

  def broadcast
    # The channel needs only the id: loading the user here was a query per alert, and progress
    # loops (doc generation, allocation) send one alert per item
    return unless user_id

    broadcast_replace_to "user_alert_#{user_id}",
                         partial: '/users/user_alert',
                         locals: { user_alert: self },
                         target: "user_alert",
                         id: "user_alert_#{Time.current.to_i}"
  end
end
