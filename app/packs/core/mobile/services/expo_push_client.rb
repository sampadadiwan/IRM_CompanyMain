# Talks to Expo's push service, which forwards to Apple (APNs) and Google (FCM)
# (lp-mobile-app design decision 5; LLD "External Integrations").
#
# One access token per region, from that region's credentials (mobile.expo_access_token) — IN
# and US never share it. Without a token the client reports itself unconfigured and push is
# simply not attempted (X20); email and WhatsApp are unaffected.
#
# Development: MOBILE_PUSH_ENABLED=true (.env.development) sends without a token — Expo accepts
# unauthenticated pushes while the project's "enhanced push security" is off — so a developer
# phone gets pushes before any token is issued.
class ExpoPushClient
  SEND_URL = "https://exp.host/--/api/v2/push/send".freeze
  RECEIPTS_URL = "https://exp.host/--/api/v2/push/getReceipts".freeze
  MAX_MESSAGES = 100
  MAX_RECEIPT_IDS = 300
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 10

  # Worth retrying: Expo 5xx, 429, timeouts (X11)
  class TransientError < StandardError; end
  # Not worth retrying: a request Expo rejects (bad token, bad payload)
  class PermanentError < StandardError; end

  def self.access_token
    Rails.application.credentials.dig(:mobile, :expo_access_token).presence
  end

  def self.configured?
    access_token.present? || ENV["MOBILE_PUSH_ENABLED"] == "true"
  end

  # @param messages [Array<Hash>] Expo message objects (≤ 100)
  # @return [Array<Hash>] one ticket per message, in order: {"status"=>"ok","id"=>…} or
  #   {"status"=>"error","details"=>{"error"=>"DeviceNotRegistered"}}
  def send_messages(messages)
    messages.each_slice(MAX_MESSAGES).flat_map { |slice| post(SEND_URL, slice).fetch("data", []) }
  end

  # @param ids [Array<String>] ticket ids (≤ 300 per call)
  # @return [Hash] ticket id => {"status"=>…, "details"=>…}
  def receipts(ids)
    ids.each_slice(MAX_RECEIPT_IDS).with_object({}) do |slice, all|
      all.merge!(post(RECEIPTS_URL, { ids: slice }).fetch("data", {}))
    end
  end

  private

  def post(url, body)
    uri = URI(url)
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request["Accept"] = "application/json"
    request["Authorization"] = "Bearer #{self.class.access_token}" if self.class.access_token.present?
    request.body = body.to_json

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: OPEN_TIMEOUT,
                                                   read_timeout: READ_TIMEOUT) { |http| http.request(request) }
    code = response.code.to_i
    raise TransientError, "Expo #{code}" if code == 429 || code >= 500
    raise PermanentError, "Expo #{code}: #{response.body.to_s.truncate(200)}" unless code.between?(200, 299)

    JSON.parse(response.body)
  rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, Errno::ECONNRESET, SocketError => e
    raise TransientError, "Expo unreachable: #{e.class}"
  rescue JSON::ParserError
    raise TransientError, "Expo returned unreadable JSON"
  end
end
