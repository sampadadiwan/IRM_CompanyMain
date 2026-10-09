module DeliveryMethods
  # WhatsApp to an employee of the notifying entity, with text the notifier builds itself
  # (notification.whatsapp_message) rather than CustomNotification#whatsapp.
  #
  # Kept separate from DeliveryMethods::WhatsApp on purpose: that one is for investors (it requires
  # an InvestorAccess with WhatsApp on) and is shared by every notifier. This one never sends to
  # anyone outside the entity, so a notifier can opt into it without any investor ever being messaged.
  # Whether the notifier wants WhatsApp at all (e.g. a workflow template's "Send WhatsApp" flag) is
  # the notifier's own deliver_by config.if — this class only enforces who may receive it.
  class EmployeeWhatsApp < Noticed::DeliveryMethod
    def deliver
      entity = notification.event.entity
      recipient = notification.recipient

      # Employees only: an investor (or anyone from another entity) is never messaged from here
      employee = recipient.entity_id == entity.id
      # Same switches every WhatsApp send honours: the entity's permission and the user's own opt-in
      allowed = entity.permissions.enable_whatsapp? && recipient.whatsapp_enabled && recipient.phone.present?
      message = notification.whatsapp_message.to_s.strip if notification.respond_to?(:whatsapp_message)

      unless employee && allowed && message.present?
        Rails.logger.info "Employee WhatsApp not sent to user #{recipient.id} for entity #{entity.name}: " \
                          "employee=#{employee} allowed=#{allowed} message=#{message.present?}"
        return
      end

      # WhatsApp shows text as typed; strip any markup the message picked up
      message = ActionView::Base.full_sanitizer.sanitize(message)
      Rails.logger.info "Sending employee WhatsApp to user #{recipient.id} from #{entity.name}"

      # Same WATI template and per-entity endpoint/token as the investor path
      endpoint = entity.entity_setting.fetch_whatsapp_endpoint
      token = entity.entity_setting.fetch_whatsapp_token
      template_name = entity.entity_setting.fetch_whatsapp_template("general_notification")
      WhatsappGeneralNotification.new.perform(entity.name, message, notification, endpoint:, token:, template_name:)
    end
  end
end
