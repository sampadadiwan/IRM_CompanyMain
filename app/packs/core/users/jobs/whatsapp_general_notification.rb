require 'uri'
require 'net/http'

class WhatsappGeneralNotification < ApplicationJob
  # TEMPLATE_NAME = ENV.fetch('CAPHIVE_NOTIFICATION')
  # link eg - "documents/90"  (template url is http://dev.altconnects.com/{{1}})

  WHATSAPP_V1_ENDPOINT = Rails.application.credentials[:WHATSAPP_API_ENDPOINT]
  WHATSAPP_V3_ENDPOINT = Rails.application.credentials[:WATI_V3_ENDPOINT]
  VERIFICATION_CODE_TEMPLATE_NAME = "code_verification".freeze

  def perform(entity_name, message, notification, endpoint: WHATSAPP_V1_ENDPOINT, token: Rails.application.credentials[:WHATSAPP_ACCESS_TOKEN], template_name: ENV.fetch('CAPHIVE_NOTIFICATION'))
    user = User.find_by(id: notification.recipient.id)
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
    request.body = {
      parameters: [
        { name: "1", value: params[:entity_name] },
        { name: "notification", value: params[:message] },
        { name: "link", value: params[:link] }
      ],
      broadcast_name: broadcast_name,
      template_name: params[:template_name]
    }.to_json

    response = http.request(request)

    response.read_body
  end

  def self.send_template_message(params, template_name:, broadcast_name: "General Notification Broadcast", endpoint: WHATSAPP_V3_ENDPOINT, token: Rails.application.credentials[:WHATSAPP_ACCESS_TOKEN])
    url = URI("#{endpoint}/api/ext/v3/messageTemplates/send")
    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(url)
    request["accept"] = 'application/json'
    request["content-type"] = 'application/json'
    request["Authorization"] = token

    body = {
      template_name: template_name,
      broadcast_name: broadcast_name,
      recipients: Array(params[:recipients]).map do |recipient|
        {
          phone_number: recipient[:phone_number],
          # local_message_id: recipient[:local_message_id],
          custom_params: Array(recipient[:custom_params]).map { |p| { name: p[:name], value: p[:value] } }
        }.compact
      end
    }
    body[:channel] = params[:channel] if params[:channel].present?

    request.body = body.to_json

    response = http.request(request)
    parse_response(response, "send_template_message")
  end

  # Sends a text message to an active conversation via v1 session message API.
  # Uses phone number as the identifier (v3 conversations endpoint not available on all plans).
  # POST /api/v1/sendSessionMessage/{whatsapp_number}?messageText={text}
  def self.send_session_message(params, endpoint: WHATSAPP_V1_ENDPOINT, token: Rails.application.credentials[:WHATSAPP_ACCESS_TOKEN])
    message = params[:message].to_s.gsub("\n", "\\n")
    encoded_message = URI.encode_www_form_component(message)
    whatsapp_number = params[:whatsapp_number]
    url = URI("#{endpoint}/api/v1/sendSessionMessage/#{whatsapp_number}?messageText=#{encoded_message}")

    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(url)
    request["Authorization"] = token

    response = http.request(request)
    response.read_body
  end

  # v3 version of send_session_message using conversation_id as target.
  # POST /api/ext/v3/conversations/messages/text
  def self.send_session_message_new(params, endpoint: WHATSAPP_V3_ENDPOINT, token: Rails.application.credentials[:WHATSAPP_ACCESS_TOKEN])
    target = params[:conversation_id]
    url = URI("#{endpoint}/api/ext/v3/conversations/messages/text")

    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(url)
    request["accept"] = 'application/json'
    request["content-type"] = 'application/json'
    request["Authorization"] = token
    request.body = { target: target, text: params[:message] }.to_json

    response = http.request(request)
    parse_response(response, "send_session_message_new")
  end

  # session document can be send to user if user has sent a message to us otherwise we need to use template messages
  def self.send_session_document(params, endpoint: WHATSAPP_V1_ENDPOINT, token: Rails.application.credentials[:WHATSAPP_ACCESS_TOKEN])
    encoded_caption = URI.encode_www_form_component(params[:caption].to_s)
    url = URI(endpoint + "/api/v1/sendSessionFile/#{params[:whatsapp_number]}?caption=#{encoded_caption}")
    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(url)
    request["content-type"] = 'multipart/form-data; boundary=---011000010111000001101001'
    request["Authorization"] = token
    doc = Document.find_by(id: params[:document_id])
    if doc.blank?
      Rails.logger.error "Error: Document not found"
      return
    elsif doc.file.blank?
      Rails.logger.error "Error: Document File empty"
      return
    end

    # zip cant be sent
    request.body = "-----011000010111000001101001\r\nContent-Disposition: form-data; name=\"file\"; filename=\"#{doc.name}\"\r\nContent-Type: #{doc.file.mime_type}\r\n\r\ndata:#{doc.file.mime_type};name=#{doc.name};base64,#{Base64.encode64(doc.file.read)}\r\n-----011000010111000001101001--"

    response = http.request(request)
    response.read_body
  end

  # v3 version of send_session_document using conversation_id as target and binary file upload.
  # POST /api/ext/v3/conversations/messages/file
  def self.send_session_document_new(params, endpoint: WHATSAPP_V3_ENDPOINT, token: Rails.application.credentials[:WHATSAPP_ACCESS_TOKEN])
    target = params[:conversation_id]

    doc = Document.find_by(id: params[:document_id])
    if doc.blank?
      Rails.logger.error "Error: Document not found"
      return
    elsif doc.file.blank?
      Rails.logger.error "Error: Document File empty"
      return
    end

    url = URI("#{endpoint}/api/ext/v3/conversations/messages/file")
    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true

    boundary = "----WATIBoundary#{SecureRandom.hex(8)}"
    file_data = doc.file.read
    caption = params[:caption].to_s

    body = build_multipart_body(boundary, target, doc.name, doc.file.mime_type, file_data, caption)

    request = Net::HTTP::Post.new(url)
    request["content-type"] = "multipart/form-data; boundary=#{boundary}"
    request["Authorization"] = token
    request.body = body

    response = http.request(request)
    parse_response(response, "send_session_document_new")
  end

  # Sends a file to an active conversation via a public URL.
  # Target is the conversation_id from the inbound webhook.
  # POST /api/ext/v3/conversations/messages/fileViaUrl
  def self.send_file_via_url(params, endpoint: WHATSAPP_V3_ENDPOINT, token: Rails.application.credentials[:WHATSAPP_ACCESS_TOKEN])
    target = params[:conversation_id]

    url = URI("#{endpoint}/api/ext/v3/conversations/messages/fileViaUrl")
    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(url)
    request["accept"] = 'application/json'
    request["content-type"] = 'application/json'
    request["Authorization"] = token

    body = { target: target, file_url: params[:file_url] }
    body[:caption] = params[:caption] if params[:caption].present?
    request.body = body.to_json

    response = http.request(request)
    parse_response(response, "send_file_via_url")
  end

  def self.build_multipart_body(boundary, target, filename, mime_type, file_data, caption)
    body = ""
    body += "--#{boundary}\r\n"
    body += "Content-Disposition: form-data; name=\"target\"\r\n\r\n"
    body += "#{target}\r\n"
    body += "--#{boundary}\r\n"
    body += "Content-Disposition: form-data; name=\"file\"; filename=\"#{filename}\"\r\n"
    body += "Content-Type: #{mime_type}\r\n\r\n"
    body = body.encode("binary")
    body += file_data.force_encoding("binary")
    body += "\r\n".encode("binary")
    if caption.present?
      body += "--#{boundary}\r\n".encode("binary")
      body += "Content-Disposition: form-data; name=\"caption\"\r\n\r\n".encode("binary")
      body += "#{caption}\r\n".encode("binary")
    end
    body += "--#{boundary}--".encode("binary")
    body
  end
  private_class_method :build_multipart_body

  def self.parse_response(response, caller_name)
    body = response.read_body
    JSON.parse(body)
  rescue JSON::ParserError
    Rails.logger.error "[WhatsappGeneralNotification##{caller_name}] HTTP #{response.code} — non-JSON body: #{body.to_s.truncate(500)}"
    { "error" => "non_json_response", "status" => response.code, "body" => body }
  end
  private_class_method :parse_response
end
