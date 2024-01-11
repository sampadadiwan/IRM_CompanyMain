module DeliveryMethods
  class WhatsAppLogger < Noticed::DeliveryMethods::Base
    def deliver
      # Get the entity name sending the msg
      entity = notification.record.entity
      # Ensure that the message is sanitized to prevent XSS attacks
      message = ActionView::Base.full_sanitizer.sanitize(notification.message)

      Rails.logger.info "Sending WhatsApp to #{notification.recipient.phone} with message #{message} from #{entity.name}"

      user = notification.recipient

      whatsapp_numbers = ApplicationMailer.new.sandbox_whatsapp_numbers(user, [user.phone_with_call_code])
      whatsapp_numbers.each do |whatsapp_number|
        # log the Notification
        entity_name_json = Notification.get_entity_name_json(message, entity.name)
        WhatsappLog.create(entity_id: entity.id, notification_id: notification.record.id, params: { entity_name: entity.name, message:, link: notification.view_path, whatsapp_number: }, entity_name: entity_name_json, name_matched: entity_name_json[entity.name.to_s] == entity.name)
      end
    end
  end
end
