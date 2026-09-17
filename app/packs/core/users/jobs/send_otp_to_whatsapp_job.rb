class SendOtpToWhatsappJob < ApplicationJob
  # The code this job carries is a TOTP value, valid for roughly 30–60 seconds after it
  # was computed at enqueue. On :default it sat behind bulk document and report
  # generation and could arrive dead. :critical is first in the server's queue list
  # (config/initializers/sidekiq.rb) and otherwise unused — same reasoning as
  # SendOtpToSmsJob.
  queue_as :critical

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

    # Strip leading '+' so the phone number matches the API's expected format (e.g. "917721046692")
    phone = user.phone_with_call_code.to_s.delete_prefix("+")

    Rails.logger.info "[SendOtpToWhatsappJob] Sending OTP via code_verification template to #{phone}"

    begin
      # Uses the "code_verification" WATI template registered on the CapHive platform account —
      # this is a single shared template across all tenants, not per-entity.
      # The custom_param name must stay "1"; it is the positional variable name assigned
      # by WATI when the template was created and cannot be changed without re-registering the template.
      response = WhatsappGeneralNotification.send_template_message(
        { recipients: [{ phone_number: phone, custom_params: [{ name: "1", value: code.to_s }] }] },
        template_name: "code_verification"
      )
      Rails.logger.info "[SendOtpToWhatsappJob] Template message sent successfully to #{phone}, response: #{response}"
    rescue StandardError => e
      Rails.logger.error "[SendOtpToWhatsappJob] Failed to send OTP to #{phone}: #{e.message}"
      raise # re-raise so ActiveJob can retry according to queue configuration
    end
  end
end
