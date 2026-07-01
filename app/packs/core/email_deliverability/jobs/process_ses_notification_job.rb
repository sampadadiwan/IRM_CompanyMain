# frozen_string_literal: true

# Parses the inner SES notification JSON (the SNS envelope's "Message" field,
# already extracted by SesNotificationsController) and records Bounce/Complaint
# events. Correlates back to the original send via the X-CapHive-Tracking-Id
# header, which SES echoes back inside mail.headers — only present for sends
# tied to a Noticed::Notification (see ApplicationMailer#tag_for_bounce_tracking).
class ProcessSesNotificationJob < ApplicationJob
  queue_as :default

  def perform(message_json)
    payload = JSON.parse(message_json)
    notification_type = payload["notificationType"]
    return unless %w[Bounce Complaint].include?(notification_type)

    tracking_id = extract_tracking_id(payload)
    notification = Noticed::Notification.find_by(tracking_id: tracking_id) if tracking_id.present?

    if notification_type == "Bounce"
      process_bounce(payload, notification, tracking_id)
    else
      process_complaint(payload, notification, tracking_id)
    end
  end

  private

  def extract_tracking_id(payload)
    headers = payload.dig("mail", "headers") || []
    header = headers.find { |h| h["name"].to_s.casecmp("X-CapHive-Tracking-Id").zero? }
    header && header["value"]
  end

  def process_bounce(payload, notification, tracking_id)
    bounce = payload["bounce"] || {}
    occurred_at = parse_time(bounce["timestamp"])

    Array(bounce["bouncedRecipients"]).each do |recipient|
      EmailBounceEvent.create!(
        noticed_notification_id: notification&.id,
        tracking_id:,
        entity_id: notification&.entity_id,
        event_type: "bounce",
        bounce_type: bounce["bounceType"],
        bounce_subtype: bounce["bounceSubType"],
        diagnostic_code: recipient["diagnosticCode"],
        recipient_email: recipient["emailAddress"],
        raw_sns_message: payload,
        occurred_at:
      )
    end

    # Report-only: this never touches InvestorAccess.email_enabled or any other record
    # besides the notification's own bounce columns (see EmailBounceEventsController#
    # disable_recipient_email for the manual, admin-triggered equivalent).
    notification&.update_columns(bounced_at: occurred_at, bounce_type: bounce["bounceType"], bounce_subtype: bounce["bounceSubType"])
  end

  def process_complaint(payload, notification, tracking_id)
    complaint = payload["complaint"] || {}
    occurred_at = parse_time(complaint["timestamp"])

    Array(complaint["complainedRecipients"]).each do |recipient|
      EmailBounceEvent.create!(
        noticed_notification_id: notification&.id,
        tracking_id:,
        entity_id: notification&.entity_id,
        event_type: "complaint",
        complaint_feedback_type: complaint["complaintFeedbackType"],
        recipient_email: recipient["emailAddress"],
        raw_sns_message: payload,
        occurred_at:
      )
    end

    notification&.update_columns(complained_at: occurred_at, complaint_feedback_type: complaint["complaintFeedbackType"])
  end

  def parse_time(value)
    if value.present?
      Time.zone.parse(value)
    else
      Rails.logger.warn("ProcessSesNotificationJob: missing SES timestamp, using Time.current")
      Time.current
    end
  rescue ArgumentError
    Rails.logger.warn("ProcessSesNotificationJob: malformed SES timestamp #{value.inspect}, using Time.current")
    Time.current
  end
end
