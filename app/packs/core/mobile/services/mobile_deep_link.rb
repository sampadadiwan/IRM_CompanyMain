# Where a notification takes the LP in the mobile app (lp-mobile-app design card ⑥ "Deep links").
#
# Capital calls, commitments, distribution payments, approval responses and documents have app screens; every other
# record opens its existing website page (the notifier's own `url`) in the in-app browser,
# prefixed "web:" so the app knows to fetch a hand-off link for it first (E15).
module MobileDeepLink
  module_function

  # The LP mobile app's fields on the website's notifications JSON. One notification whose record
  # has since been deleted must not break the whole list (the website's own JSON), so this fails
  # safe to a link to the website's notifications page.
  def notification_fields(notification)
    # sender_id lets the app show only the selected fund manager's alerts (lp-mobile-multi-site MF-H4)
    { message: notification.message.to_s, sender: notification.event&.entity&.name,
      sender_id: notification.event&.entity_id,
      link: self.for(notification), category: MobilePushCategory.for(notification.event) }
  rescue StandardError => e
    Rails.logger.warn("[mobile_deep_link] notification #{notification.id}: #{e.class}: #{e.message}")
    { message: "", sender: nil, sender_id: nil, link: "web:/notifications", category: "other" }
  end

  def for(notification)
    record = notification.event&.record

    case record
    when CapitalRemittance then "/capital-calls/#{record.id}"
    when CapitalCommitment then "/funds/#{record.id}"
    when CapitalDistributionPayment then "/distributions/#{record.id}"
    when ApprovalResponse then "/approvals/#{record.id}"
    when Document then "/documents/#{record.id}"
    else web_link(notification)
    end
  end

  # The website path only — the host differs per region and is added by the hand-off (card ⑦)
  def web_link(notification)
    url = notification.url.to_s
    path = url.start_with?("/") ? url : URI.parse(url).request_uri
    "web:#{path.presence || '/'}"
  rescue URI::InvalidURIError, NoMethodError
    "web:/"
  end
end
