# frozen_string_literal: true

# One row per SES bounce/complaint notification received via SesNotificationsController.
# Bounce tracking is scoped to notifier-driven sends only — noticed_notification is nil
# when SES couldn't correlate the notification (see ProcessSesNotificationJob).
# Report-only: creating a row here never changes InvestorAccess.email_enabled or any
# other record automatically (see EmailBounceEventsController#disable_recipient_email
# for the manual, admin-triggered equivalent).
class EmailBounceEvent < ApplicationRecord
  belongs_to :noticed_notification, class_name: "Noticed::Notification", optional: true
  belongs_to :entity, optional: true

  enum :event_type, { bounce: "bounce", complaint: "complaint" }

  validates :event_type, presence: true
  validates :recipient_email, presence: true
  validates :occurred_at, presence: true

  scope :for_entity, ->(entity_id) { where(entity_id: entity_id) }
  scope :hard_bounces, -> { bounce.where(bounce_type: "Permanent") }
end
