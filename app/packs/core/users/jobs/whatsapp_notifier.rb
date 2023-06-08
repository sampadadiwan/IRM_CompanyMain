require 'uri'
require 'net/http'
require 'openssl'

DEFAULT_WHATSAPP_MSG = "How can we help you?".freeze

class WhatsappNotifier < ApplicationJob
  # call perform_later with params
  # templates can have variables in them, so params will include template name and template_params
  def perform(params, user = nil)
    template_name = params["template_name"].to_s
    case template_name
    when ENV.fetch('ACC_UPDATE_NOTI_TEMPLATE')
      params = if params.key?('template_params')
                 params['template_params']
               elsif user.present?
                 { "whatsapp_no" => user.phone_with_call_code, "user_name" => user.name }
               else
                 {}
               end
      self.class.send_acc_update_alert_notification(params)
    when "default", ""
      params = if params.key?('template_params')
                 params['template_params']
               elsif user.present?
                 { "whatsapp_no" => user.phone_with_call_code }
               end
      self.class.send_message(params["whatsapp_no"], params["message"])
    else
      Rails.logger.error "Error: template_name has an invalid value (#{template_name})"
    end
  end

  def self.send_message(whatsapp_no, message = DEFAULT_WHATSAPP_MSG)
    if whatsapp_no.blank?
      Rails.logger.error "Whatsapp Number not present"
      return
    end
    message = Addressable::URI.encode message # other methods were replacing space with + whereas it should be %20
    url = URI(Rails.application.credentials[:WHATSAPP_API_ENDPOINT] + "/api/v1/sendSessionMessage/#{whatsapp_no}?messageText=#{message}")
    http = get_http(url)
    request = get_post_request url
    response = http.request(request)
    response.read_body
  end

  def self.get_messages(number, page_size = 10, page_number = 1)
    url = URI("#{Rails.application.credentials[:WHATSAPP_API_ENDPOINT]}/api/v1/getMessages/#{number}?pageSize=#{page_size}&pageNumber=#{page_number}")
    http = get_http url
    request = get_get_request url
    response = http.request(request)
    response.read_body
  end

  def self.send_acc_update_alert_notification(template_params)
    whatsapp_no = template_params["whatsapp_no"]
    user_name = template_params["user_name"]
    if whatsapp_no.blank? || user_name.blank?
      Rails.logger.error "Invalid params for update alert notification - #{template_params}"
      return
    end

    url = URI(Rails.application.credentials[:WHATSAPP_API_ENDPOINT] + "/api/v1/sendTemplateMessage?whatsappNumber=#{whatsapp_no}")
    http = get_http url
    request = get_post_request url
    request["content-type"] = 'text/json'
    request.body = "{\"parameters\":[{\"name\":\"name\",\"value\":\"#{user_name}\"}],\"broadcast_name\":\"Acc Update\",\"template_name\":\"account_update_alert_1\"}"
    response = http.request(request)
    response.read_body
  end

  def self.get_http(url)
    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true
    http
  end

  def self.get_post_request(url)
    request = Net::HTTP::Post.new(url)
    request["Authorization"] = Rails.application.credentials[:WHATSAPP_ACCESS_TOKEN]
    request
  end

  def self.get_get_request(url)
    request = Net::HTTP::Get.new(url)
    request["Authorization"] = Rails.application.credentials[:WHATSAPP_ACCESS_TOKEN]
    request
  end
end
