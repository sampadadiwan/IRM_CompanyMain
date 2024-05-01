module WithCustomNotifications
  extend ActiveSupport::Concern

  included do
    has_many :noticed_events, as: :record, dependent: :destroy, class_name: "Noticed::Event"

    has_many :custom_notifications, as: :owner, dependent: :destroy
  end

  def custom_notification(email_method, for_type: nil, custom_notification_id: nil)
    # Get the last notification for the email method which is enabled
    cns = custom_notifications.enabled.where(email_method:)
    cns = cns.where(for_type:) if for_type.present?
    cns = cns.where(id: custom_notification_id) if custom_notification_id.present?
    cns.last
  end
end
