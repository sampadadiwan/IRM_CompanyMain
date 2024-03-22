module DeliveryMethods
  class WhatsApp < Noticed::DeliveryMethod
    def deliver
      # Get the entity name sending the msg
      entity = notification.event.entity

      if notification.recipient.whatsapp_enabled && entity.permissions.enable_whatsapp?

        # Ensure that the message is sanitized to prevent XSS attacks
        message = ActionView::Base.full_sanitizer.sanitize(notification.message)

        Rails.logger.info "Sending WhatsApp to #{notification.recipient.phone} with message #{message} from #{entity.name}"

        # Get the endpoint and token from the entity settings
        endpoint = entity.entity_setting.fetch_whatsapp_endpoint
        token = entity.entity_setting.fetch_whatsapp_token
        template_name = entity.entity_setting.fetch_whatsapp_template("general_notification")
        # Send the message
        WhatsappGeneralNotification.new.perform(entity.name, message,
                                                notification, endpoint:, token:, template_name:)
      else
        Rails.logger.info "WhatsApp not enabled for #{notification.recipient.phone} and entity #{entity.name}"
      end
    end
  end
end
