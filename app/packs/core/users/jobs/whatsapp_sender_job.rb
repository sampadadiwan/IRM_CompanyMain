class WhatsappSenderJob < ApplicationJob
  queue_as :low

  def perform(msg, user)
    if user.whatsapp_enabled
      send(msg, user.phone)
    else
      Rails.logger.debug "Whatsapp msg not sent. User has not enabled it"
    end
  end

  def send(msg, phone)
    phone = "+91#{phone}" unless phone.starts_with?("+91")

    uri = URI.parse("https://api.gupshup.io/sm/api/v1/msg")
    request = Net::HTTP::Post.new(uri)
    request.content_type = "application/x-www-form-urlencoded"
    request["Cache-Control"] = "no-cache"
    request["Apikey"] = (ENV['WHATSAPP_API_KEY']).to_s
    request.set_form_data(
      "channel" => "whatsapp",
      "destination" => phone,
      "message" => "{\"type\":\"text\",\"text\":\"#{msg}\"}",
      "source" => (ENV['WHATSAPP_SOURCE_PHONE']).to_s,
      "src.name" => "AltConnects"
    )

    req_options = {
      use_ssl: uri.scheme == "https"
    }

    response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
      http.request(request)
    end

    logger.debug "Whatsapp msg to #{phone}, Response Code: #{response.code}, Response Body: #{response.body}"
  end
end
