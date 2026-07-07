module DeliveryMethods
  class WhatsApp < Noticed::DeliveryMethod
    def deliver
      # Get the entity name sending the msg
      entity = notification.event.entity
      # Get the user we are sending the message to
      recipient = notification.recipient
      # Get the investor access for the recipient as setup by the entity
      investor_access = entity.investor_accesses.where(email: recipient.email).first

      whatsapp_enabled = recipient.whatsapp_enabled && investor_access&.whatsapp_enabled && entity.permissions.enable_whatsapp?

      if whatsapp_enabled

        # No fallback to notification.message here, by design - and no blank check needed either:
        # the :whats_app deliver_by's config.if (NotificationExtensions#custom_notification_whatsapp_present?)
        # already guarantees this only runs with a populated whatsapp field, since WhatsApp has no
        # default message to fall back to in the first place.
        # Ensure that the message is sanitized to prevent XSS attacks
        message = ActionView::Base.full_sanitizer.sanitize(notification.custom_notification.whatsapp)

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
