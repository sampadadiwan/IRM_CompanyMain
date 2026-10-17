# frozen_string_literal: true

# Stands in for Expo's push service in @expo-push scenarios (lp-mobile-app push_delivery.feature).
# Records every message sent, answers with one ticket per message, and can be told to fail:
# a ticket error for one phone's address, a receipt error, or a whole-request status (503).
class ExpoPushRecorder
  attr_reader :messages
  attr_accessor :status, :ticket_errors, :receipt_errors

  def initialize
    @messages = []
    @status = 200
    @ticket_errors = {}   # push token => Expo error code
    @receipt_errors = {}  # push token => Expo error code
    @tickets = {}         # ticket id => push token
  end

  def send_response(request)
    return { status: @status, body: "{}" } unless @status == 200

    batch = JSON.parse(request.body)
    @messages.concat(batch)
    data = batch.map do |message|
      if (error = ticket_errors[message["to"]])
        { status: "error", message: error, details: { error: } }
      else
        id = SecureRandom.uuid
        @tickets[id] = message["to"]
        { status: "ok", id: }
      end
    end
    { status: 200, body: { data: }.to_json, headers: { "Content-Type" => "application/json" } }
  end

  def receipts_response(request)
    ids = JSON.parse(request.body).fetch("ids")
    data = ids.to_h do |id|
      error = receipt_errors[@tickets[id]]
      [id, error ? { status: "error", details: { error: } } : { status: "ok" }]
    end
    { status: 200, body: { data: }.to_json, headers: { "Content-Type" => "application/json" } }
  end

  def to(token) = messages.select { |m| m["to"] == token }
end

Before("@expo-push") do
  require "webmock/cucumber"
  WebMock.enable!
  WebMock.disable_net_connect!(allow_localhost: true)
  @expo = ExpoPushRecorder.new
  recorder = @expo
  WebMock::API.stub_request(:post, ExpoPushClient::SEND_URL).to_return { |req| recorder.send_response(req) }
  WebMock::API.stub_request(:post, ExpoPushClient::RECEIPTS_URL).to_return { |req| recorder.receipts_response(req) }
  # The region's Expo access token (credentials mobile.expo_access_token)
  allow(ExpoPushClient).to receive(:access_token).and_return("test-expo-token")
end

After("@expo-push") do
  WebMock.reset!
  WebMock.allow_net_connect!
  WebMock.disable!
end
