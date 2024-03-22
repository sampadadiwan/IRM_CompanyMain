require 'uri'
require 'net/http'

class WhatsappGeneralNotification < ApplicationJob
  # TEMPLATE_NAME = ENV.fetch('CAPHIVE_NOTIFICATION')
  # link eg - "documents/90"  (template url is http://dev.altconnects.com/{{1}})
  def perform(entity_name, message, notification, endpoint: Rails.application.credentials[:WHATSAPP_API_ENDPOINT], token: Rails.application.credentials[:WHATSAPP_ACCESS_TOKEN], template_name: ENV.fetch('CAPHIVE_NOTIFICATION'))
    user = User.find(notification.recipient.id)
    if user.blank?
      Rails.logger.error "Error: User required to send Whatsapp Notification"
      return
    elsif user.present? && (!user.whatsapp_enabled || user.phone.blank?)
      Rails.logger.error "Error: Whatsapp Not Enabled or Invalid Number for User ID #{user.id}"
      return
    end

    link = notification.url
    whatsapp_numbers = ApplicationMailer.new.sandbox_whatsapp_numbers(notification.event, [user.phone_with_call_code])
    whatsapp_numbers.each do |whatsapp_number|
      params = { entity_name:, message:, link:, whatsapp_number:, endpoint:, token:, template_name: }
      self.class.send_message(params)

      # rubocop:disable Rails/SkipsModelValidations
      notification.update_columns(whatsapp_sent: true, whatsapp: { to: whatsapp_number, params: { entity_name:, message:, link: } }.to_json)
      # rubocop:enable Rails/SkipsModelValidations
    end
  end

  def self.send_message(params)
    url = URI(params[:endpoint] + "/api/v1/sendTemplateMessage?whatsappNumber=#{params[:whatsapp_number]}")
    broadcast_name = "General Notification Broadcast"
    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(url)
    request["content-type"] = 'text/json'
    request["Authorization"] = params[:token]
    request.body = "{\"parameters\":[{\"name\":\"1\",\"value\":\"#{params[:entity_name]}\"},{\"name\":\"notification\",\"value\":\"#{params[:message]}\"},{\"name\":\"link\",\"value\":\"#{params[:link]}\"}],\"broadcast_name\":\"#{broadcast_name}\",\"template_name\":\"#{params[:template_name]}\"}"

    response = http.request(request)

    response.read_body
  end
end
