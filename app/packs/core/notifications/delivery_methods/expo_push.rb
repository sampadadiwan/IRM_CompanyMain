module DeliveryMethods
  # Push for the LP mobile app, declared once on BaseNotifier so every investor notifier gets it
  # (lp-mobile-app design card ⑥). Whether it runs at all is BaseNotifier's `config.if`
  # (NotificationExtensions#push_enabled — the email gate plus the push checks); this sends one
  # message per live, push-enabled phone of the recipient.
  #
  # Idempotent: a delivery row per (notification, phone) is created BEFORE the HTTP call and a
  # phone already marked sent is skipped, so a retried job never pushes twice (E35). A push failure
  # raises only for transient Expo errors (X11) — Noticed retries this delivery alone; email and
  # WhatsApp are separate deliveries and are unaffected.
  class ExpoPush < Noticed::DeliveryMethod
    # Lock screens show about two lines; long subjects are cut with an ellipsis (E14)
    MAX_BODY = 178

    def deliver
      devices = notification.recipient.mobile_devices.pushable.to_a
      return if devices.empty?

      # One delivery row per phone; phones already pushed for this notification are skipped
      pending = devices.filter_map do |device|
        delivery = MobilePushDelivery.find_or_create_by!(noticed_notification_id: notification.id, mobile_device_id: device.id)
        [device, delivery] unless %w[sent delivered].include?(delivery.status)
      rescue ActiveRecord::RecordNotUnique
        nil # a concurrent retry already claimed this phone
      end
      return if pending.empty?

      message = build_message
      tickets = ExpoPushClient.new.send_messages(pending.map { |device, _| message.merge(to: device.push_token) })
      record_tickets(pending, tickets)
    end

    private

    # H11 title = the sending fund manager; H12 body = the subject, custom wording included
    def build_message
      {
        title: notification.event.entity&.name.to_s,
        body: ActionView::Base.full_sanitizer.sanitize(notification.message.to_s).squish.truncate(MAX_BODY),
        # region + fund_manager_id: a tap first switches the app to the region and fund manager the
        # notification is about, then opens it (lp-mobile-multi-site MF-H5, MS-H5)
        data: { link: MobileDeepLink.for(notification), notification_id: notification.id,
                region: SiteRegistry.current_code_or_nil, fund_manager_id: notification.event.entity_id },
        badge: notification.recipient.notifications.unread.count,
        sound: "default"
      }
    end

    # Receipts (did Apple/Google accept it?) are checked later by the ExpoPushReceiptsJob sweep
    def record_tickets(pending, tickets)
      pending.each_with_index do |(device, delivery), i|
        ticket = tickets[i] || {}
        if ticket["status"] == "ok"
          delivery.update!(status: "sent", ticket_id: ticket["id"], error: nil)
          device.update_columns(last_push_at: Time.current)
        else
          error = ticket.dig("details", "error") || ticket["message"] || "no ticket"
          delivery.update!(status: "failed", error: error.to_s.truncate(255))
          # X10 — the app was uninstalled / reinstalled: stop pushing to this address
          device.mark_not_registered! if error == "DeviceNotRegistered"
        end
      end
    end
  end
end
