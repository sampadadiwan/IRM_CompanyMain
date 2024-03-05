module WithCustomNotifications
  extend ActiveSupport::Concern

  included do
    has_noticed_notifications
    has_many :custom_notifications, as: :owner, dependent: :destroy
  end

  def custom_notification(email_method, for_type: nil)
    cns = custom_notifications.where(email_method:)
    cns = cns.where(for_type:) if for_type.present?
    cns.last
  end
end
