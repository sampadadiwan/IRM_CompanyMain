require 'uri'
require 'net/http'

class WhatsappGeneralNotification < ApplicationJob
  TEMPLATE_NAME = ENV.fetch('CAPHIVE_NOTIFICATION')
  # link eg - "documents/90"  (template url is http://dev.altconnects.com/{{1}})
  def perform(entity_name, message, link, user_id, notification_id)
    user = User.find(user_id)
    if user.blank?
      Rails.logger.error "Error: User required to send Whatsapp Notification"
      return
    elsif user.present? && (!user.whatsapp_enabled || user.phone.blank?)
      Rails.logger.error "Error: Whatsapp Not Enabled or Invalid Number for User ID #{user.id}"
      return
    end

    notification = Notification.find(notification_id)

    whatsapp_numbers = ApplicationMailer.new.sandbox_whatsapp_numbers(notification, [user.phone_with_call_code])
    whatsapp_numbers.each do |whatsapp_number|
      self.class.send_message(entity_name, message, link, whatsapp_number)
      # log the Notification
      Notification.get_entity_name_json(message, entity_name)

      # rubocop:disable Rails/SkipsModelValidations
      notification.update_columns(whatsapp_sent: true, whatsapp: { to: whatsapp_number, params: { entity_name:, message:, link: } }.to_json)
      # rubocop:enable Rails/SkipsModelValidations
    end
  end

  def self.send_message(entity_name, message, link, whatsapp_no)
    url = URI(Rails.application.credentials[:WHATSAPP_API_ENDPOINT] + "/api/v1/sendTemplateMessage?whatsappNumber=#{whatsapp_no}")
    broadcast_name = "General Notification Broadcast"
    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(url)
    request["content-type"] = 'text/json'
    request["Authorization"] = Rails.application.credentials[:WHATSAPP_ACCESS_TOKEN]
    request.body = "{\"parameters\":[{\"name\":\"1\",\"value\":\"#{entity_name}\"},{\"name\":\"notification\",\"value\":\"#{message}\"},{\"name\":\"link\",\"value\":\"#{link}\"}],\"broadcast_name\":\"#{broadcast_name}\",\"template_name\":\"#{TEMPLATE_NAME}\"}"

    response = http.request(request)

    response.read_body
  end
end
