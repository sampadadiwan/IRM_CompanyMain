# The only place that talks HTTP to Zoho Sign: region addresses, access tokens, timeouts and the
# mapping of Zoho failures onto typed errors. Every call is made on one ZohoSignAccount (CapHive's
# platform account or a company's own connection) - the caller picks the account, never this class.
#
# Paths are from zoho esign docs/Zoho Sign API.postman_collection.json.
class ZohoSignClient
  Region = Data.define(:name, :accounts_host, :sign_host)

  # Single source of Zoho's data centres. Canada (zohocloud.ca) is verified against a sandbox
  # before release - see the change's design risks.
  REGIONS = {
    "com" => Region.new(name: "United States", accounts_host: "accounts.zoho.com", sign_host: "sign.zoho.com"),
    "eu" => Region.new(name: "Europe", accounts_host: "accounts.zoho.eu", sign_host: "sign.zoho.eu"),
    "in" => Region.new(name: "India", accounts_host: "accounts.zoho.in", sign_host: "sign.zoho.in"),
    "jp" => Region.new(name: "Japan", accounts_host: "accounts.zoho.jp", sign_host: "sign.zoho.jp"),
    "com.au" => Region.new(name: "Australia", accounts_host: "accounts.zoho.com.au", sign_host: "sign.zoho.com.au"),
    "ca" => Region.new(name: "Canada", accounts_host: "accounts.zohocloud.ca", sign_host: "sign.zohocloud.ca"),
    "sa" => Region.new(name: "Saudi Arabia", accounts_host: "accounts.zoho.sa", sign_host: "sign.zoho.sa"),
    "uk" => Region.new(name: "United Kingdom", accounts_host: "accounts.zoho.uk", sign_host: "sign.zoho.uk"),
    "sg" => Region.new(name: "Singapore", accounts_host: "accounts.zoho.sg", sign_host: "sign.zoho.sg"),
    "ae" => Region.new(name: "UAE", accounts_host: "accounts.zoho.ae", sign_host: "sign.zoho.ae")
  }.freeze

  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 30
  DOWNLOAD_READ_TIMEOUT = 60
  # Zoho access tokens live an hour; refresh a minute early so a token never expires mid-call.
  TOKEN_EXPIRY_MARGIN = 60

  class Error < StandardError; end

  # Zoho refused the credentials (or, during connect, the grant code). reason is one of
  # :invalid_code, :invalid_client, :invalid_secret or :unauthorized.
  class AuthError < Error
    attr_reader :reason

    def initialize(message = nil, reason: :unauthorized)
      @reason = reason
      super(message)
    end
  end

  # Zoho answered 429 / "too many requests" - background jobs retry these later.
  class RateLimited < Error; end
  # Timeouts, connection failures and 5xx - background jobs retry these later.
  class TransientError < Error; end
  # Any other refusal (4xx); message is Zoho's own explanation.
  class RequestError < Error; end

  NETWORK_ERRORS = [Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET,
                    Errno::EHOSTUNREACH, OpenSSL::SSL::SSLError].freeze

  TOKEN_ERRORS = {
    "invalid_code" => :invalid_code,
    "invalid_client" => :invalid_client,
    "invalid_client_secret" => :invalid_secret
  }.freeze

  attr_reader :account

  def self.region!(key)
    REGIONS.fetch(key.to_s) { raise ArgumentError, "Unknown Zoho region #{key.inspect}" }
  end

  # Redeems a Self Client grant code (single use, ~10 minutes) for a refresh token. Nothing about
  # the call is logged - its query carries the client secret and code.
  def self.exchange_grant_code(region:, client_id:, client_secret:, code:)
    json = token_request(region, client_id:, client_secret:, code:, grant_type: "authorization_code")
    json["refresh_token"].presence || raise(AuthError.new("Zoho returned no refresh token", reason: :invalid_code))
  end

  def self.token_request(region, **query)
    response = HTTParty.post("https://#{region!(region).accounts_host}/oauth/v2/token", query:,
                                                                                        open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT)
    raise TransientError, "Zoho accounts answered #{response.code}" if response.code >= 500

    json = parse_json(response.body)
    error = json["error"].to_s
    return json if error.blank? && response.success?

    raise RateLimited, "Zoho token requests rate limited" if error.casecmp?("Access Denied") || response.code == 429
    raise AuthError.new("Zoho rejected the credentials (#{error.presence || response.code})", reason: TOKEN_ERRORS.fetch(error, :unauthorized)) if error.present? || response.code == 401

    raise RequestError, "Zoho token request failed (#{response.code})"
  rescue *NETWORK_ERRORS => e
    raise TransientError, "Zoho accounts unreachable - #{e.message}"
  end

  def self.parse_json(body)
    body.present? ? JSON.parse(body) : {}
  rescue JSON::ParserError
    {}
  end

  def initialize(account)
    @account = account
  end

  def region
    self.class.region!(account.region)
  end

  # Creates a draft request with the file; returns Zoho's "requests" hash.
  def create_request(data:, file:)
    call(:post, "/api/v1/requests", body: { data: data.to_json, file: }, multipart: true).fetch("requests", {})
  end

  # /submit takes the payload as a "data" form field, like /requests - not a JSON body.
  def submit_request(request_id, actions)
    call(:post, "/api/v1/requests/#{request_id}/submit", body: { data: { requests: { actions: } }.to_json })
  end

  def get_request(request_id)
    call(:get, "/api/v1/requests/#{request_id}")
  end

  def download_pdf(request_id)
    call(:get, "/api/v1/requests/#{request_id}/pdf", raw: true, read_timeout: DOWNLOAD_READ_TIMEOUT)
  end

  def completion_certificate(request_id)
    call(:get, "/api/v1/requests/#{request_id}/completioncertificate", raw: true, read_timeout: DOWNLOAD_READ_TIMEOUT)
  end

  def recall(request_id)
    call(:post, "/api/v1/requests/#{request_id}/recall")
  end

  def remind(request_id)
    call(:post, "/api/v1/requests/#{request_id}/remind")
  end

  # Zoho reads expire_by as "dd Month yyyy" - a machine format for its API, not a screen date.
  def extend(request_id, date)
    call(:put, "/api/v1/requests/#{request_id}/extend", body: { expire_by: date.strftime("%d %B %Y") })
  end

  def delete_request(request_id)
    call(:put, "/api/v1/requests/#{request_id}/delete")
  end

  # Cheapest call that proves the stored credentials work (needs only the documents READ scope).
  def list_requests_probe
    call(:get, "/api/v1/requests", query: { data: { page_context: { row_count: 1, start_index: 1 } }.to_json })
  end

  def access_token
    Rails.cache.read(account.token_cache_key) || refresh_access_token
  end

  private

  # A 401 with a cached token usually means the token was revoked or expired early: drop it,
  # refresh once and retry once. A second 401 means the credentials themselves are refused.
  def call(verb, path, raw: false, read_timeout: READ_TIMEOUT, retried: false, **)
    response = HTTParty.send(verb, "https://#{region.sign_host}#{path}",
                             headers: { "Authorization" => "Zoho-oauthtoken #{access_token}" },
                             open_timeout: OPEN_TIMEOUT, read_timeout:, **)
    log(verb, path, response)

    if response.code == 401
      credentials_rejected!(AuthError.new("Zoho rejected the access token for #{path}", reason: :unauthorized)) if retried

      Rails.cache.delete(account.token_cache_key)
      return call(verb, path, raw:, read_timeout:, retried: true, **)
    end

    handle(response, raw:)
  rescue *NETWORK_ERRORS => e
    raise TransientError, "Zoho Sign unreachable (#{path}) - #{e.message}"
  end

  def handle(response, raw:)
    raise RateLimited, "Zoho Sign rate limited" if response.code == 429
    raise TransientError, "Zoho Sign answered #{response.code}" if response.code >= 500

    json = raw ? {} : self.class.parse_json(response.body)
    raise RequestError, json["message"].presence || "Zoho Sign answered #{response.code}" unless response.success? && json["status"] != "failure"

    raw ? response.body : json
  end

  def refresh_access_token
    json = self.class.token_request(account.region, refresh_token: account.refresh_token, client_id: account.client_id,
                                                    client_secret: account.client_secret, grant_type: "refresh_token")
    token = json["access_token"].presence || raise(AuthError, "Zoho returned no access token")
    expires_in = [json.fetch("expires_in", 3600).to_i - TOKEN_EXPIRY_MARGIN, TOKEN_EXPIRY_MARGIN].max
    Rails.cache.write(account.token_cache_key, token, expires_in: expires_in.seconds)
    token
  rescue AuthError => e
    credentials_rejected!(e)
  end

  # Nobody can fix CapHive's own credentials from the app, so that case alerts developers.
  def credentials_rejected!(error)
    ErrorReport.notify(error, source: "ZohoSignClient platform") if account.platform?
    raise error
  end

  # Path and Zoho's code/message only - never headers or bodies, which carry tokens and documents.
  def log(verb, path, response)
    json = response.headers["content-type"].to_s.include?("json") ? self.class.parse_json(response.body) : {}
    Rails.logger.info { "ZohoSign #{verb.upcase} #{path} -> #{response.code} #{json.slice('code', 'message').to_json}" }
  end
end
