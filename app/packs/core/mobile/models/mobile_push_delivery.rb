# One push of one notification to one phone (lp-mobile-app design card ⑥).
# The unique (notification, device) pair is what makes a retried delivery job harmless (E35).
class MobilePushDelivery < ApplicationRecord
  STATUSES = %w[pending sent delivered failed].freeze

  belongs_to :noticed_notification, class_name: "Noticed::Notification"
  belongs_to :mobile_device

  validates :status, inclusion: { in: STATUSES }
  validates :ticket_id, length: { maximum: 64 }
  validates :error, length: { maximum: 255 }
end
