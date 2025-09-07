# app/services/sync_api_client.rb
# frozen_string_literal: true

# SyncApiClient (HTTParty, no mTLS)
# -----------------------------------------------------------------------------
# Endpoints on each region (HTTPS):
#   POST /internal/sync/users        → UPSERT snapshot
#   POST /internal/sync/users/disable→ DISABLE user
#
# Auth: HMAC header over "#{method}\n#{path}\n#{timestamp}\n#{sha256(body)}"
#   X-Region:          <origin_region>      # caller's region (primary)
#   X-Timestamp:       <ISO8601 UTC>        # replay protection (±300s on server)
#   X-Idempotency-Key: <event_id>           # dedupe
#   X-Signature:       <hex>                # HMAC-SHA256
#
# Config:
#   - Base URLs are fixed by region (caphive.us / .com / .sg)
#   - HMAC secrets pulled from Rails credentials or ENV (see bottom)
#
require "httparty"
require "openssl"
require "json"
require "securerandom"

class SyncApiClient
  include HTTParty

  class Error < StandardError; end
  class RetryableError < Error; end
  class FatalError < Error; end

  DEFAULT_TIMEOUT = 10 # seconds (HTTParty's :timeout covers open/read)

  REGION_BASE_URLS = if Rails.env.production?
                       {
                         "US" => "https://caphive.us/",
                         "IN" => "https://caphive.com/",
                         "SG" => "https://caphive.sg/"
                       }.freeze
                     else
                       {
                         "US" => "https://dev.altconnects.us/",
                         "IN" => "https://dev.altconnects.com/",
                         "SG" => "https://dev.altconnects.sg/"
                       }.freeze
                     end

  USER_AGENT = "CapHive-SyncClient/httpparty-1.0"

  # ---- Public API -----------------------------------------------------------

  # Send UPSERT snapshot
  # @param target_region [String] "US"|"IN"|"SG"
  # @param envelope [Hash] built by UserSyncEnvelopeBuilder
  # @return [Hash] parsed JSON response
  def self.post_user_upsert!(target_region:, envelope:)
    region = norm_region(target_region)
    base   = base_url_for!(region)
    path   = "/internal/sync/users"
    body   = JSON.generate(envelope)
    ts     = Time.now.utc.iso8601(3)
    # The HMAC secret should be based on the origin_region, as that's what's sent in the X-Region header
    origin_region_for_signing = norm_region(envelope[:origin_region] || envelope["origin_region"])
    sig = signature(:post, path, ts, body, hmac_secret_for!(origin_region_for_signing))

    request_json!(
      url: URI.join(base, path).to_s,
      body: body,
      headers: {
        "Content-Type" => "application/json",
        "Accept" => "application/json",
        "User-Agent" => USER_AGENT,
        "X-Region" => norm_region(envelope[:origin_region] || envelope["origin_region"]),
        "X-Timestamp" => ts,
        "X-Idempotency-Key" => envelope[:event_id] || envelope["event_id"] || SecureRandom.uuid,
        "X-Signature" => sig
      }
    )
  end

  # Send DISABLE
  # @param target_region [String]
  # @param email [String]
  # @param origin_region [String]
  # @param reason [String]
  # @param event_id [String,nil]
  def self.post_user_disable!(target_region:, email:, origin_region:, reason:, event_id: nil)
    region  = norm_region(target_region)
    base    = base_url_for!(region)
    path    = "/internal/sync/users/disable"
    payload = {
      action: "DISABLE",
      event_id: event_id || SecureRandom.uuid,
      as_of: Time.now.utc.iso8601(3),
      origin_region: norm_region(origin_region),
      target_region: region,
      email: email.to_s.strip.downcase,
      reason: reason.to_s
    }
    body = JSON.generate(payload)
    ts   = Time.now.utc.iso8601(3)
    # The HMAC secret should be based on the origin_region, as that's what's sent in the X-Region header
    origin_region_for_signing = norm_region(payload[:origin_region] || payload["origin_region"])
    sig = signature(:post, path, ts, body, hmac_secret_for!(origin_region_for_signing))

    request_json!(
      url: URI.join(base, path).to_s,
      body: body,
      headers: {
        "Content-Type" => "application/json",
        "Accept" => "application/json",
        "User-Agent" => USER_AGENT,
        "X-Region" => payload[:origin_region],
        "X-Timestamp" => ts,
        "X-Idempotency-Key" => payload[:event_id],
        "X-Signature" => sig
      }
    )
  end

  # ---- Internals ------------------------------------------------------------

  def self.request_json!(url:, body:, headers:)
    Rails.logger.debug { "[SyncApiClient] Request: url=#{url}, headers=#{headers.except('X-Signature')}, body=#{truncate(body)}" }

    res = HTTParty.post(
      url,
      body: body,
      headers: headers,
      timeout: DEFAULT_TIMEOUT, # covers open/read in HTTParty
      verify: true # HTTPS server cert verification (no client certs)
    )

    code = res.code.to_i
    parsed = parse_json_safely(res.body.to_s)

    Rails.logger.debug { "[SyncApiClient] Response: status=#{code}, body=#{truncate(res.body)}" }

    case code
    when 200..299
      parsed
    when 408, 425, 429, 500..599
      raise RetryableError, "retryable status #{code}: #{truncate(res.body)}"
    when 401, 403
      raise FatalError, "auth error #{code}: #{truncate(res.body)}"
    when 409
      raise FatalError, "conflict #{code}: #{truncate(res.body)}"
    when 400, 404, 422
      raise FatalError, "client error #{code}: #{truncate(res.body)}"
    else
      raise RetryableError, "unexpected status #{code}: #{truncate(res.body)}"
    end
  rescue HTTParty::Error, SocketError, Timeout::Error => e
    Rails.logger.error("[SyncApiClient] Network failure: #{e.class}: #{e.message}")
    raise RetryableError, "network failure: #{e.class}: #{e.message}"
  end
  private_class_method :request_json!

  def self.signature(method, path, timestamp, body_json, secret)
    data = "#{method.to_s.upcase}\n#{path}\n#{timestamp}\n#{sha256_hex(body_json)}"
    OpenSSL::HMAC.hexdigest("SHA256", secret.to_s, data)
  end
  private_class_method :signature

  def self.sha256_hex(string_value)
    OpenSSL::Digest::SHA256.hexdigest(string_value)
  end
  private_class_method :sha256_hex

  def self.base_url_for!(region)
    REGION_BASE_URLS.fetch(region) { raise FatalError, "unknown region #{region}" }
  end
  private_class_method :base_url_for!

  def self.hmac_secret_for!(region)
    # Prefer credentials; fallback to ENV
    cred = begin
      Rails.application.credentials.dig(:sync_api, :secrets, region)
    rescue StandardError
      nil
    end
    # This is only used for tests
    env = ENV.fetch("SYNC_API_HMAC_#{region}", nil)
    secret = cred.presence || env.presence
    raise FatalError, "missing HMAC secret for region=#{region} (credentials or ENV SYNC_API_HMAC_#{region})" if secret.blank?

    secret
  end
  private_class_method :hmac_secret_for!

  def self.norm_region(region_value)
    region_value.to_s.strip.upcase
  end
  private_class_method :norm_region

  def self.parse_json_safely(body)
    return {} if body.to_s.strip.empty?

    JSON.parse(body)
  rescue JSON::ParserError
    { "raw" => body }
  end
  private_class_method :parse_json_safely

  def self.truncate(string_value, max = 400)
    str = string_value.to_s
    str.length > max ? "#{str[0, max]}..." : str
  end
  private_class_method :truncate
end
