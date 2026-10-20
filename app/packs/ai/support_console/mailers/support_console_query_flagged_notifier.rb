# frozen_string_literal: true

# In-app alert to CapHive super users when a Support Console lookup returned rows belonging to a
# client other than the conversation's (E15, X10). Internal only: no email, no WhatsApp, not
# customisable — the bell is the channel.
#
# @see openspec/changes/support-console/design.md#notifications
class SupportConsoleQueryFlaggedNotifier < BaseNotifier
  required_param :entity_id

  # BaseNotifier requires a mailer name; delivery by email is switched off below.
  def mailer_name(_notification = nil)
    nil
  end

  notification_methods do
    # In-app only: the email and WhatsApp deliveries BaseNotifier declares never fire.
    def custom_notification_body_present?
      false
    end

    def email_enabled
      false
    end

    def whatsapp_enabled
      false
    end

    def message
      query = record
      "Support Console lookup flagged: #{query.user.full_name} asking about #{query.entity.name} read another client's rows"
    end

    def url
      Rails.application.routes.url_helpers.admin_support_console_queries_path(flagged: true)
    end
  end
end
