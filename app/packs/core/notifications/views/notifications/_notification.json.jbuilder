json.extract! notification, :id, :recipient_id, :recipient_type, :type, :params, :read_at, :created_at, :updated_at
json.url notification_url(notification, format: :json)
# LP mobile app Alerts tab (lp-mobile-app H9, E15): the text shown, who sent it, and where a tap goes
json.merge! MobileDeepLink.notification_fields(notification)
