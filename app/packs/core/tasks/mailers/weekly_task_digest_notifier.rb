# frozen_string_literal: true

# Noticed event for the weekly task digest — one per recipient, raised by
# WeeklyTaskDigestJob. See docs/product/weekly_task_digest_prd.md.
#
# Going through a notifier rather than calling TaskDigestMailer directly is what buys
# the digest everything the rest of the app's outgoing mail already has: a
# Noticed::Notification row (so the digest appears in the in-app bell and in the
# notifications report), SES bounce/complaint correlation via
# ApplicationMailer#tag_for_bounce_tracking, the per-entity send delay, and the
# entity/investor-access email toggles in BaseNotifier's deliver_by conditions.
#
# `record` is the RECIPIENT, not a task. A digest has no single subject row, and
# NotificationExtensions#email_enabled dereferences `model.entity_id` — which Entity
# does not have and User does. Using the recipient makes that check trivially true
# (a fund employee is always allowed their own entity's mail) and gives the in-app
# notification a sensible owner.
#
# The three section counts ride along in params so #message can render the in-app
# text without rebuilding the digest — the email rebuilds it at delivery time anyway,
# and the bell should not run six aggregate queries to draw one line of text.
class WeeklyTaskDigestNotifier < BaseNotifier
  required_param :entity_id

  def mailer_name(_notification = nil)
    TaskDigestMailer
  end

  def email_method(_notification = nil)
    :weekly_digest
  end

  def email_data(notification)
    {
      notification_id: notification.id,
      user_id: notification.recipient_id,
      entity_id: params[:entity_id],
      as_of: params[:as_of]
    }
  end

  notification_methods do
    def message
      delayed = params[:delayed_count].to_i
      due = params[:due_next_week_count].to_i
      status = delayed.zero? ? "all on track" : "#{delayed} delayed"
      "Weekly tasks: #{status}, #{due} due next week"
    end

    # No CustomNotification for the digest: the body is a rendered report, not client
    # boilerplate. Returning nil keeps the email deliver_by condition true and the
    # WhatsApp one false — see NotificationExtensions.
    def custom_notification
      nil
    end

    def url
      tasks_path(sub_domain: record.entity.sub_domain)
    end
  end
end
