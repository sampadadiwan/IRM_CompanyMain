# frozen_string_literal: true

# Parses the inner SES notification JSON (the SNS envelope's "Message" field,
# already extracted by SesNotificationsController) and records Bounce/Complaint
# events. Correlates back to the original send via the X-CapHive-Tracking-Id
# header, which SES echoes back inside mail.headers — only present for sends
# tied to a Noticed::Notification (see ApplicationMailer#tag_for_bounce_tracking).
class ProcessSesNotificationJob < ApplicationJob
  queue_as :default

  def perform(message_json)
    payload = parse_payload(message_json)
    return if payload.nil?

    notification_type = event_type(payload)
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

  # Not every message on the topic is a JSON event. When a configuration set event
  # destination is created, SES publishes a plain-text confirmation to the topic:
  #
  #   "Successfully validated SNS topic for Amazon SES event publishing."
  #
  # JSON.parse raises on it, and because this is an ActiveJob that means Sidekiq retries a
  # message that can never parse - 25 times with backoff, reporting an exception each time.
  # Observed in staging the moment the destination was created. Anything unparseable is
  # logged and dropped instead.
  def parse_payload(message_json)
    parsed = JSON.parse(message_json)
    # A bare JSON scalar parses without raising but is not an event. Guarding on Hash keeps
    # the lookups below from silently doing something else - String#[] with a string
    # argument returns a substring rather than nil, so payload["eventType"] on a String is
    # quietly wrong rather than an error.
    return parsed if parsed.is_a?(Hash)

    Rails.logger.info("Ignoring non-object message on the SES topic: #{message_json.to_s.truncate(150)}")
    nil
  rescue JSON::ParserError
    Rails.logger.info("Ignoring non-JSON message on the SES topic: #{message_json.to_s.truncate(150)}")
    nil
  end

  # SES names this field differently depending on how the events were wired:
  #
  #   eventType         - configuration set event publishing (what we use; see
  #                       lib/tasks/ses_bounce_setup.rake)
  #   notificationType  - the legacy identity-level Bounce/Complaint topics
  #
  # AWS states this outright: "If you did not set up event publishing this field is named
  # notificationType." Reading only notificationType meant every real event fell through the
  # `return unless` below and nothing was ever recorded - while SesNotificationsController
  # still rendered 200, so SNS counted the delivery as successful and the whole pipeline
  # looked healthy end to end. Caught only by an empty email_bounce_events table after
  # staging was wired and confirmed delivering.
  #
  # Both are accepted so either wiring works.
  def event_type(payload)
    payload["eventType"].presence || payload["notificationType"].presence
  end

  def extract_tracking_id(payload)
    headers = payload.dig("mail", "headers") || []
    header = headers.find { |h| h["name"].to_s.casecmp("X-CapHive-Tracking-Id").zero? }
    header && header["value"]
  end

  def process_bounce(payload, notification, tracking_id)
    bounce = payload["bounce"] || {}
    occurred_at = parse_time(bounce["timestamp"])

    record_events(Array(bounce["bouncedRecipients"]), occurred_at) do |recipient|
      {
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
      }
    end

    # Report-only: this never touches InvestorAccess.email_enabled or any other record
    # besides the notification's own bounce columns (see EmailBounceEventsController#
    # disable_recipient_email for the manual, admin-triggered equivalent).
    notification&.update_columns(bounced_at: occurred_at, bounce_type: bounce["bounceType"], bounce_subtype: bounce["bounceSubType"])
  end

  def process_complaint(payload, notification, tracking_id)
    complaint = payload["complaint"] || {}
    occurred_at = parse_time(complaint["timestamp"])

    record_events(Array(complaint["complainedRecipients"]), occurred_at) do |recipient|
      {
        noticed_notification_id: notification&.id,
        tracking_id:,
        entity_id: notification&.entity_id,
        event_type: "complaint",
        complaint_feedback_type: complaint["complaintFeedbackType"],
        recipient_email: recipient["emailAddress"],
        raw_sns_message: payload,
        occurred_at:
      }
    end

    notification&.update_columns(complained_at: occurred_at, complaint_feedback_type: complaint["complaintFeedbackType"])
  end

  # One transaction, and idempotent per (tracking_id, recipient, event_type).
  #
  # Both matter. SNS is at-least-once, so the same event can legitimately arrive twice and
  # there is no unique index to stop it duplicating rows. And without the transaction, a
  # recipient entry missing emailAddress fails the model's presence validation partway
  # through - the earlier rows are already committed, the job raises, Sidekiq retries it 25
  # times, and every attempt re-commits those same rows before failing again.
  #
  # A recipient with no address is skipped rather than fatal: one malformed entry should not
  # discard the rest of a real bounce report.
  def record_events(recipients, occurred_at)
    return if recipients.empty? || occurred_at.nil?

    EmailBounceEvent.transaction do
      recipients.each do |recipient|
        attrs = yield(recipient)
        email = attrs[:recipient_email].presence
        next Rails.logger.warn("Skipping SES recipient with no emailAddress (tracking_id=#{attrs[:tracking_id]})") if email.nil?

        existing = EmailBounceEvent.find_by(tracking_id: attrs[:tracking_id], recipient_email: email,
                                            event_type: attrs[:event_type], occurred_at: attrs[:occurred_at])
        next if existing

        EmailBounceEvent.create!(attrs)
      end
    end
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
