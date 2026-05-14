module DeliveryMethods
  class UserAlerts < Noticed::DeliveryMethods::Base
    def deliver
      # Logic for sending the notification
      message = ActionController::Base.helpers.link_to(notification.message.html_safe, Rails.application.routes.url_helpers.notification_url(id: notification.record.id))

      UserAlert.new(message:, user_id: notification.recipient.id, level: "info").broadcast
    end

    # You may override this method to validate options for the delivery method
    # Invalid options should raise a ValidationError
    #
    # def self.validate!(options)
    #   raise ValidationError, "required_option missing" unless options[:required_option]
    # end
  end
end
