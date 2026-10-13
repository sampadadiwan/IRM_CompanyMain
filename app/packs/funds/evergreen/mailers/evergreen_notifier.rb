# Evergreen investor emails (proposal US-13), sent instead of call and distribution notices.
# Recipients: Investor#notification_users(record) — the investor's users and the advisors approved to
# see that order (or folio), checked against the record's own policy. The record is the order
# (fill-level emails pass fill_id) or, for folio-level emails, the folio (CapitalCommitment).
# Optional emails are sent only when switched on for the fund (EvergreenFundSetting#notify?).
# Worked examples H7, H21, H25, E32 — openspec/changes/open-ended-funds/design.md#worked-examples
class EvergreenNotifier < BaseNotifier
  required_param :email_method, :entity_id

  def mailer_name(_notification = nil)
    EvergreenMailer
  end

  def email_data(notification)
    {
      notification_id: notification.id,
      user_id: notification.recipient_id,
      entity_id: params[:entity_id],
      dealing_order_id: (record.id if record.is_a?(DealingOrder)),
      capital_commitment_id: (record.id if record.is_a?(CapitalCommitment)),
      dealing_fill_id: params[:dealing_fill_id],
      fund_nav_id: params[:fund_nav_id],
      unlocked_units: params[:unlocked_units],
      fund_id: record.fund_id,
      investor_id: record.investor_id,
      from_email: record.fund.custom_fields.from_email
    }
  end

  notification_methods do
    def message
      # Same wording as the email subject, in the fund's labels
      EvergreenMailer.subject_for(params[:email_method], record.fund, order: (record if record.is_a?(DealingOrder)))
    end

    # Review fix 6a: the fund's Evergreen template for this email, the same one EvergreenMailer uses.
    # Noticed's :whats_app delivery (BaseNotifier) only fires when the notifier answers
    # custom_notification with a template whose WhatsApp text is filled in
    # (NotificationExtensions#custom_notification_whatsapp_present?). Without this method evergreen
    # messages were never sent on WhatsApp, although the template's WhatsApp field could be edited.
    def custom_notification
      @custom_notification ||= record.fund.custom_notification(params[:email_method].to_s, for_type: "Evergreen")
    end

    def url
      helpers = Rails.application.routes.url_helpers
      record.is_a?(DealingOrder) ? helpers.evergreen_order_path(record.fund_id, record.id) : helpers.fund_path(record.fund_id)
    end
  end

  class << self
    def order_received(order)
      deliver(order, order.subscription? ? :subscription_acknowledgement : :redemption_acknowledgement)
    end

    def order_cancelled(order)
      deliver(order, :request_cancelled)
    end

    def order_rolled(order)
      deliver(order, :request_rolled)
    end

    def gate_notice(fill)
      deliver(fill.dealing_order, :gate_notice, fill)
    end

    def payment_instructions(fill)
      deliver(fill.dealing_order, :payment_instructions, fill)
    end

    def contract_note(fill)
      deliver(fill.dealing_order, :contract_note, fill)
    end

    def redemption_advice(fill)
      deliver(fill.dealing_order, :redemption_advice, fill)
    end

    # ---- open-ended-funds § Notifications (optional, per-fund switches) ----
    def payment_reminder(order) = deliver(order, :payment_reminder)
    def action_needed(order) = deliver(order, :action_needed)
    def payment_received(order) = deliver(order, :payment_received)

    def units_unlocked(folio, units)
      deliver(folio, :units_unlocked, nil, unlocked_units: units.to_s)
    end

    def nav_update(folio, fund_nav)
      deliver(folio, :nav_update, nil, fund_nav_id: fund_nav.id)
    end

    private

    # record: the order, or the folio for folio-level emails
    def deliver(record, email_method, fill = nil, **extra)
      setting = record.fund.evergreen_fund_setting
      return if EvergreenFundSetting::NOTIFICATIONS.key?(email_method.to_s) && !setting&.notify?(email_method)

      users = record.investor.notification_users(record)
      return if users.blank?

      with(record:, entity_id: record.entity_id, email_method:, dealing_fill_id: fill&.id, **extra).deliver_later(users)
    end
  end
end
