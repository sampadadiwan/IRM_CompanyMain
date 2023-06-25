class UserAlert < ApplicationRecord
  belongs_to :user
  belongs_to :entity

  after_save_commit :broadcast_ua, on: %i[create update]
  validates :level, length: { maximum: 8 }

  def broadcast
    broadcast_replace_to [user, "user_alert"],
                         partial: '/users/user_alert',
                         locals: { user_alert: self },
                         target: "user_alert"
  end
end
