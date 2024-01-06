module DeliveryMethods
  class WhatsApp < Noticed::DeliveryMethods::Base
    def deliver
      # Get the entity name sending the msg
      entity = notification.record.entity

      if notification.recipient.whatsapp_enabled && entity.permissions.enable_whatsapp?

        # Ensure that the message is sanitized to prevent XSS attacks
        message = ActionView::Base.full_sanitizer.sanitize(notification.message)

        Rails.logger.info "Sending WhatsApp to #{notification.recipient.phone} with message #{message} from #{entity.name}"

        # Send the message
        WhatsappGeneralNotification.new.perform(entity.name, message,
                                                notification.view_path,
                                                notification.recipient.id,
                                                notification.record.id) # pass id
      else
        Rails.logger.info "WhatsApp not enabled for #{notification.recipient.phone} and entity #{entity.name}"
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
