module DeliveryMethods
  class WhatsApp < Noticed::DeliveryMethods::Base
    def deliver
      if notification.recipient.whatsapp_enabled
        # Get the entity name sending the msg
        entity = notification.record.entity
        # Ensure that the message is sanitized to prevent XSS attacks
        message = ActionView::Base.full_sanitizer.sanitize(notification.message)
        # Send the message
        WhatsappGeneralNotification.new.perform(entity.name, message,
                                                notification.view_path,
                                                notification.recipient.id)
      else
        Rails.logger.info "WhatsApp not enabled for #{notification.recipient.phone}"
      end
    end

    # You may override this method to validate options for the delivery method
    # Invalid options should raise a ValidationError
    #
    # def self.validate!(options)
    #   raise ValidationError, "required_option missing" unless options[:required_option]
    # end
  end
end
