module DeliveryMethods
  class WhatsApp < Noticed::DeliveryMethod
    def deliver
      # Get the entity name sending the msg
      entity = notification.event.entity
      # Get the user we are sending the message to
      recipient = notification.recipient
      # Is WhatsApp on for the investor access of the folio this notification is about? Resolved by
      # NotificationExtensions#folio_channel_enabled? - the same answer the :whats_app gate used -
      # rather than "the recipient's first access in the fund", which read another folio's switch
      # for anyone holding accesses on more than one folio (report E3).
      folio_whatsapp_enabled = notification.folio_channel_enabled?(:whatsapp_enabled)

      whatsapp_enabled = recipient.whatsapp_enabled && folio_whatsapp_enabled && entity.permissions.enable_whatsapp?

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
