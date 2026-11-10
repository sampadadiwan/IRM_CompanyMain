# frozen_string_literal: true

# The admin alert's email + bell (OWASP review 2026-11 M11, design card ⑦). Recipients are chosen by
# SecurityEventAlert only; this class only says how to deliver. Not a CustomNotification: it is CapHive's own
# security alert, and a firm can't mute it (design "Notifications").
class SecurityEventNotifier < BaseNotifier
  required_param :entity_id

  def mailer_name(_notification = nil)
    SecurityEventsMailer
  end

  def email_method(_notification = nil)
    :admin_alert
  end

  def email_data(notification)
    { notification_id: notification.id, user_id: notification.recipient_id, entity_id: params[:entity_id],
      security_event_id: record.id }
  end

  notification_methods do
    # H33 / E42 / C19 — support sign-ins and firm switches are announced in the bell only, never by email — user
    # decision 2026-11-09.
    # BaseNotifier's email delivery is gated on this predicate (`config.if`, in every environment), so returning
    # false here skips the email and keeps the bell. Every other security alert still emails.
    def custom_notification_body_present?
      return false if SecurityEventAlert.bell_only?(event.record)

      super
    end

    # The bell: the same sentence as the email subject
    def message
      SecurityEventAlert.headline(record)
    end

    def url
      security_events_path
    end
  end
end
