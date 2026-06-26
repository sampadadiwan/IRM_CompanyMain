class SendOtpToWhatsappJob < ApplicationJob
  queue_as :default

  def perform(user_id, code)
    user = User.find(user_id)

    Rails.logger.info "[SendOtpToWhatsappJob] Starting for user_id=#{user_id}, email=#{user.email}, phone=#{user.phone_with_call_code}, whatsapp_enabled=#{user.whatsapp_enabled?}"

    unless user.whatsapp_enabled?
      Rails.logger.warn "[SendOtpToWhatsappJob] Aborting — WhatsApp not enabled for user_id=#{user_id}"
      return
    end

    unless user.phone.present?
      Rails.logger.warn "[SendOtpToWhatsappJob] Aborting — no phone number for user_id=#{user_id}"
      return
    end

    message = "Your IRM verification code is: #{code}. It expires in 30 seconds."
    phone = user.phone_with_call_code
    endpoint = Rails.application.credentials[:WHATSAPP_API_ENDPOINT]
    token = Rails.application.credentials[:WHATSAPP_ACCESS_TOKEN]

    Rails.logger.info "[SendOtpToWhatsappJob] endpoint=#{endpoint}"
    Rails.logger.info "[SendOtpToWhatsappJob] Sending OTP via WhatsApp session message to #{phone}"

    begin
      response = WhatsappGeneralNotification.send_session_message(
        { whatsapp_number: phone, message: message },
        endpoint: endpoint,
        token: token
      )
      Rails.logger.info "[SendOtpToWhatsappJob] Session message response: #{response}"
      Rails.logger.info "[SendOtpToWhatsappJob] Session message sent successfully to #{phone}"
    rescue StandardError => e
      Rails.logger.warn "[SendOtpToWhatsappJob] Session message failed for #{phone}: #{e.message}"
      entity = user.entity
      if entity&.entity_setting&.fetch_whatsapp_endpoint.present?
        Rails.logger.info "[SendOtpToWhatsappJob] Falling back to template message for #{phone}"
        WhatsappGeneralNotification.send_message(
          endpoint: entity.entity_setting.fetch_whatsapp_endpoint,
          token: entity.entity_setting.fetch_whatsapp_token,
          template_name: entity.entity_setting.fetch_whatsapp_template(:otp_verification),
          whatsapp_number: phone,
          entity_name: entity.name,
          message: "Your verification code is: #{code}",
          link: ""
        )
        Rails.logger.info "[SendOtpToWhatsappJob] Template message sent successfully to #{phone}"
      else
        Rails.logger.warn "[SendOtpToWhatsappJob] No WhatsApp endpoint configured for entity #{entity&.id}, cannot send fallback"
      end
    end
  end
end
